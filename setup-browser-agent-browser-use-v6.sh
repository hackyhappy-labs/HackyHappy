#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  AI 브라우저 에이전트 + Multi-Agent — v6.4.0                                ║
# ║  제작자: <webmaster@vulva.sex>
# Multi-Agent 업그레이드: v6.4.0 (Groq+LangGraph)                                       ║
# ║                                                                      ║
# ║  주요 기능:                                                          ║
# ║  - Browser Use + Playwright 자동 설치 (DOM+A11y 하이브리드)         ║
# ║  - Docker 네트워크 자동 연결 (open-webui ↔ browser-agent)           ║
# ║  - Self-Healing 재시도 + CVE 패치 적용 (2026-05)                    ║
# ║  - Tool v4.2.0: check_weather, check_price, check_stock 등 11개     ║
# ║  - 한글 우회: 영어→한국어 자동 매핑 (Groq 모델 호환)               ║
# ║  - API 키 자동 치환 + 도구 update/create 자동 등록                  ║
# ║  - VNC 포트 127.0.0.1 바인딩 + UFW 방화벽 검증                     ║
# ║  - secrets sudo chmod + seccomp + non-root + rate limiting          ║
# ║                                                                      ║
# ║  보안: seccomp, cap_drop, no-new-privileges, API 키 인증,           ║
# ║        감사 로그, VNC 일회용 토큰, .env 600 권한                    ║
# ╚══════════════════════════════════════════════════════════════════════╝
set -euo pipefail
IFS=$'\n\t'

# ── [WSL2/Windows 자가 치유] CRLF → LF 변환 ──────────────────────────
_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
if file "$_SELF" 2>/dev/null | grep -q "CRLF"; then
    echo -e "\033[1;33m⚠️   CRLF 줄바꿈 감지 → 자동 변환 후 재실행합니다...\033[0m"
    sed -i 's/\r//' "$_SELF"
    exec bash "$_SELF" "$@"
fi
unset _SELF

# ── 색상 및 유틸 ──────────────────────────────────────────────────────
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'
C='\033[0;36m'; B='\033[1m'; N='\033[0m'
ok()    { echo -e "${G}✅  $*${N}"; }
warn()  { echo -e "${Y}⚠️   $*${N}"; }
err()   { echo -e "${R}❌  $*${N}"; exit 1; }
info()  { echo -e "${C}ℹ️   $*${N}"; }
step()  { echo -e "\n${B}══ $* ══${N}"; }
masked() {
    local s="$1"; local len=${#s}
    if [ "$len" -le 8 ]; then echo "${s:0:2}****${s: -2}"
    else echo "${s:0:4}****${s: -4}"; fi
}

# [FIX-11] 이메일 형식 검증
validate_email() {
    local e="$1"
    [[ "$e" =~ ^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$ ]]
}

INPUT_TIMEOUT=120
timeout_exit() {
    echo -e "${R}⏰ 입력 시간 초과 (${INPUT_TIMEOUT}초) — 다시 실행하세요:${N}"
    echo "   bash setup-browser-agent-browser-use-v6.sh"
    exit 1
}

echo -e "${B}"
cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════════╗
║  AI Browser Use Agent + Multi-Agent — v6.4.0  (Browser-Use + CVE보안강화)             ║
╚══════════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${N}"

# ══════════════════════════════════════════════════════════════════════
# SECTION 0 — 경로 및 자격증명
# ══════════════════════════════════════════════════════════════════════
OWUI_DIR="${HOME}/OpenWebUI"
AGENT_DIR="${OWUI_DIR}/browser-agent"
SECRETS_DIR="${AGENT_DIR}/secrets"
COMPOSE_FILE="${OWUI_DIR}/docker-compose.yml"
ENV_FILE="${OWUI_DIR}/.env"

# Phase 2 디렉토리
TOOLS_API_DIR="${OWUI_DIR}/tools-api"
TWILIO_BOT_DIR="${OWUI_DIR}/twilio-bot"

# Phase 3 디렉토리
TELEGRAM_DIR="${HOME}/telegram-openwebui-bridge"

# 임시파일: /dev/shm (메모리 기반) — EXIT 시 보안 삭제
TOOL_TMP="/dev/shm/owui_tool_$(python3 -c 'import secrets; print(secrets.token_hex(8))').py"
trap 'python3 -c "
import os
for p in [\"${TOOL_TMP}\"]:
    if os.path.exists(p):
        sz = max(os.path.getsize(p), 1)
        with open(p, \"r+b\") as f:
            f.write(os.urandom(sz)); f.flush(); os.fsync(f.fileno())
        os.remove(p)
" 2>/dev/null; true' EXIT

_env() { grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 \
         | cut -d= -f2- | tr -d "\"'" | xargs 2>/dev/null || true; }

# ── OpenWebUI 컨테이너 이름 자동 감지 ────────────────────────────────
OWUI_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i 'open-webui' | grep -v tools | head -1 || true)
if [ -n "$OWUI_CONTAINER" ]; then
    # [FIX] Docker Compose 서비스명 사용 (컨테이너명 대신 — 네트워크 안정성 향상)
    OPENWEBUI_INTERNAL_URL="http://open-webui:8080"
    ok "OpenWebUI 컨테이너 감지: ${OWUI_CONTAINER} → 서비스명 open-webui 사용"
else
    OPENWEBUI_INTERNAL_URL="http://open-webui:8080"
    warn "OpenWebUI 컨테이너 자동 감지 실패 → http://open-webui:8080 사용"
fi

# [FIX-10] OWUI_HOST 하드코딩 제거 — .env 또는 입력값 사용
OWUI_HOST=""
ADMIN_EMAIL=""; ADMIN_PASS=""

if [ -f "$ENV_FILE" ]; then
    [[ -z "$ADMIN_EMAIL" ]] && ADMIN_EMAIL="$(_env WEBUI_ADMIN_EMAIL)"
    [[ -z "$ADMIN_EMAIL" ]] && ADMIN_EMAIL="$(_env ADMIN_EMAIL)"
    [[ -z "$ADMIN_PASS"  ]] && ADMIN_PASS="$(_env WEBUI_ADMIN_PASSWORD)"
    [[ -z "$ADMIN_PASS"  ]] && ADMIN_PASS="$(_env ADMIN_PASSWORD)"
    _h="$(_env WEBUI_URL)"; [[ -n "$_h" ]] && OWUI_HOST="$_h"
fi

if [ -z "$OWUI_HOST" ]; then
    echo -e "${Y}OpenWebUI 외부 URL을 입력하세요 (예: https://your-domain.com):${N}"
    read -t "$INPUT_TIMEOUT" -r -p "  🌐 URL: " OWUI_HOST || timeout_exit
    OWUI_HOST="${OWUI_HOST%/}"
    [[ "$OWUI_HOST" =~ ^https?:// ]] || err "URL은 http:// 또는 https://로 시작해야 합니다."
fi

# ── 관리자 계정 입력 ──────────────────────────────────────────────────
if [ -z "$ADMIN_EMAIL" ]; then
    echo -e "${Y}OpenWebUI 관리자 이메일 (${INPUT_TIMEOUT}초 내 입력):${N}"
    while true; do
        read -t "$INPUT_TIMEOUT" -r -p "  📧 이메일: " ADMIN_EMAIL || timeout_exit
        validate_email "$ADMIN_EMAIL" && break
        warn "유효하지 않은 이메일 형식입니다. 다시 입력하세요."
    done
fi

# 관리자 비밀번호 입력 (화면 표시)
if [ -z "$ADMIN_PASS" ]; then
    echo -e "${Y}OpenWebUI 관리자 비밀번호 (${INPUT_TIMEOUT}초 내 입력):${N}"
    read -t "$INPUT_TIMEOUT" -r -p "  🔒 비밀번호: " ADMIN_PASS || timeout_exit
    [[ ${#ADMIN_PASS} -ge 6 ]] || err "비밀번호가 너무 짧습니다 (최소 6자)."
fi

# ── OpenWebUI API 키 입력 ──────────────────────────────────────────────
EXISTING_OWUI_API_KEY="$(_env OPENWEBUI_API_KEY)"
if [ -n "$EXISTING_OWUI_API_KEY" ] && [ ${#EXISTING_OWUI_API_KEY} -ge 20 ]; then
    OWUI_API_KEY="$EXISTING_OWUI_API_KEY"
    info "OpenWebUI API 키 재사용: $(masked "$OWUI_API_KEY")"
else
    echo ""
    echo -e "${Y}OpenWebUI API 키 입력 (${INPUT_TIMEOUT}초 내):${N}"
    echo -e "${C}  발급: OpenWebUI → 설정 → 계정 → API Keys → 새 키 생성${N}"
    while true; do
        read -t "$INPUT_TIMEOUT" -r -s -p "  🔑 API Key: " OWUI_API_KEY || timeout_exit
        echo ""
        OWUI_API_KEY=$(echo "$OWUI_API_KEY" | xargs)
        if [ ${#OWUI_API_KEY} -ge 20 ]; then
            _VERIFY=$(curl -s --connect-timeout 5 --max-time 10 -o /dev/null \
                -w "%{http_code}" -H "Authorization: Bearer ${OWUI_API_KEY}" \
                "${OWUI_HOST}/api/v1/auths/" 2>/dev/null || echo "000")
            if [ "$_VERIFY" = "200" ]; then
                ok "OpenWebUI API 키 검증 성공: $(masked "$OWUI_API_KEY")"
                break
            else
                warn "API 키 검증 실패 (HTTP ${_VERIFY}). 그래도 계속 진행하시겠습니까? (y/N)"
                read -t 30 -r _CONT || timeout_exit
                [[ "$_CONT" =~ ^[Yy]$ ]] && break
            fi
        else
            warn "API 키가 너무 짧습니다 (최소 20자). 다시 입력하세요."
        fi
    done
fi

# ── 자동 생성 키들 ──────────────────────────────────────────────────────
EXISTING_API_KEY="$(_env BROWSER_AGENT_API_KEY)"
if [ -n "$EXISTING_API_KEY" ] && [ ${#EXISTING_API_KEY} -ge 64 ]; then
    BROWSER_API_KEY="$EXISTING_API_KEY"
    info "기존 Browser API 키 재사용: $(masked "$BROWSER_API_KEY")"
else
    BROWSER_API_KEY=$(python3 -c "import secrets; print(secrets.token_hex(64))")
    ok "새 Browser API 키 생성 (512비트): $(masked "$BROWSER_API_KEY")"
fi

# [v6] VNC 제거됨 — VNC_PASSWORD 불필요

EXISTING_INT_TOKEN="$(_env BROWSER_INTERNAL_TOKEN)"
if [ -n "$EXISTING_INT_TOKEN" ] && [ ${#EXISTING_INT_TOKEN} -ge 32 ]; then
    INTERNAL_TOKEN="$EXISTING_INT_TOKEN"
else
    INTERNAL_TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(32))")
fi

SERVER_HOST=$(echo "$OWUI_HOST" | sed 's|https\?://||' | cut -d/ -f1)
# [v6] VNC 제거됨 — VNC_WEB_URL 불필요

# ── .env 저장 ──────────────────────────────────────────────────────────
_save_env() {
    local K="$1" V="$2"
    # [FIX] 특수문자 안전 처리 — base64로 인코딩 후 Python에서 디코딩
    local V_B64
    V_B64=$(python3 -c "import base64,sys; print(base64.b64encode(sys.argv[1].encode()).decode())" "$V")
    if grep -q "^${K}=" "$ENV_FILE" 2>/dev/null; then
        python3 - "$K" "$V_B64" "$ENV_FILE" << 'PYSAVE'
import re, sys, base64
k, vb64, ep = sys.argv[1], sys.argv[2], sys.argv[3]
v = base64.b64decode(vb64).decode()
with open(ep) as f: ct = f.read()
ct = re.sub(r'^' + re.escape(k) + r'=.*', k + '=' + v, ct, flags=re.MULTILINE)
with open(ep, 'w') as f: f.write(ct)
PYSAVE
    else
        local V_PLAIN
        V_PLAIN=$(python3 -c "import base64,sys; print(base64.b64decode(sys.argv[1]).decode())" "$V_B64")
        printf '\n%s=%s\n' "$K" "$V_PLAIN" >> "$ENV_FILE"
    fi
}

for KV in \
    "BROWSER_AGENT_API_KEY=${BROWSER_API_KEY}" \
    "GROQ_MODEL=${GROQ_MODEL:-llama-3.3-70b-versatile}" \
    "SERVER_HOST=${SERVER_HOST}" \
    "BROWSER_INTERNAL_TOKEN=${INTERNAL_TOKEN}" \
    "OPENWEBUI_API_KEY=${OWUI_API_KEY}" \
    "WEBUI_URL=${OWUI_HOST}"; do
    _save_env "${KV%%=*}" "${KV#*=}"
done
chmod 600 "$ENV_FILE"
ok ".env 저장 완료 (chmod 600)"
ok "Browser API 키: $(masked "$BROWSER_API_KEY") | Engine: Browser Use"

# [FIX-12] .bak 파일 정리 (최근 5개만 보존)
_cleanup_bak() {
    local DIR="$1" PATTERN="$2"
    local COUNT
    COUNT=$(find "$DIR" -maxdepth 1 -name "$PATTERN" 2>/dev/null | wc -l)
    if [ "$COUNT" -gt 5 ]; then
        find "$DIR" -maxdepth 1 -name "$PATTERN" | sort | head -n $((COUNT-5)) | xargs rm -f
        info ".bak 파일 정리 완료 (최근 5개 보존)"
    fi
}

# ══════════════════════════════════════════════════════════════════════
# SECTION 0-A — 시스템 사양 자동 감지
# ══════════════════════════════════════════════════════════════════════
step "0/9  시스템 사양 감지"

TOTAL_RAM_MB=$(python3 -c "
import os
try:
    with open('/proc/meminfo') as f:
        for l in f:
            if l.startswith('MemTotal'):
                print(int(l.split()[1]) // 1024); break
except Exception: print(0)
" 2>/dev/null || echo "0")

CPU_CORES=$(python3 -c "import os; print(os.cpu_count() or 1)" 2>/dev/null || echo "1")
FREE_DISK_GB=$(df -BG "${HOME}" 2>/dev/null | python3 -c "
import sys
lines = sys.stdin.read().strip().split('\n')
if len(lines) >= 2:
    parts = lines[1].split()
    print(parts[3].replace('G','') if len(parts) >= 4 else 0)
else: print(0)
" 2>/dev/null || echo "0")
info "RAM: ${TOTAL_RAM_MB}MB | CPU: ${CPU_CORES}코어 | 디스크 여유: ${FREE_DISK_GB}GB"

IS_WSL=false
if grep -qEi "Microsoft|WSL" /proc/version &>/dev/null; then
    IS_WSL=true; ok "WSL2 환경 감지"
    warn "WSL2: runc openat2 호환성을 위해 privileged 모드로 실행됩니다."
    info "보안 강화를 원하면 PowerShell에서 'wsl --update' 후 재설치하세요."
fi

HAS_GPU=false
if command -v nvidia-smi &>/dev/null && nvidia-smi | grep -q "NVIDIA"; then
    HAS_GPU=true; ok "NVIDIA GPU 감지"
fi

# 모드 설정
LITE_MODE=false
BUILD_START_PERIOD="45s"; MAX_WAIT=90; CONTAINER_MEMORY="2G"
CONTAINER_CPUS="1.5"; SHM_SIZE="512mb"
SCREEN_RESOLUTION="1280x800x24"; MAX_STEPS_AGENT=10

if [ "$TOTAL_RAM_MB" -lt 8192 ]; then
    LITE_MODE=true
    warn "저사양 모드 (RAM ${TOTAL_RAM_MB}MB < 8GB)"
    BUILD_START_PERIOD="120s"; MAX_WAIT=240; CONTAINER_MEMORY="3G"
    CONTAINER_CPUS="2.0"; SHM_SIZE="256mb"
    SCREEN_RESOLUTION="1024x768x24"; MAX_STEPS_AGENT=7
elif [ "$TOTAL_RAM_MB" -ge 16384 ]; then
    ok "고화질 모드 (RAM ${TOTAL_RAM_MB}MB >= 16GB)"
    BUILD_START_PERIOD="30s"; MAX_WAIT=60; CONTAINER_MEMORY="4G"
    CONTAINER_CPUS="2.5"; SHM_SIZE="1024mb"
    SCREEN_RESOLUTION="1920x1080x24"; MAX_STEPS_AGENT=15
fi

[ "$CPU_CORES" -lt 2 ] && warn "CPU 코어 부족 (${CPU_CORES}코어)"
[ "${FREE_DISK_GB}" -lt 8 ] 2>/dev/null && warn "디스크 여유 공간 부족: ${FREE_DISK_GB}GB (권장 8GB+)"
info "설정: MEM=${CONTAINER_MEMORY} CPU=${CONTAINER_CPUS} SHM=${SHM_SIZE} RES=${SCREEN_RESOLUTION}"

# ══════════════════════════════════════════════════════════════════════
# SECTION 1 — 사전 조건 확인
# ══════════════════════════════════════════════════════════════════════
step "2/9  사전 조건 확인"
[ -d "$OWUI_DIR" ]     || err "OpenWebUI 디렉토리 없음: $OWUI_DIR"
[ -f "$COMPOSE_FILE" ] || err "docker-compose.yml 없음: $COMPOSE_FILE"
command -v docker    &>/dev/null || err "Docker 필요"
docker compose version &>/dev/null || err "Docker Compose 플러그인 필요"
command -v python3   &>/dev/null || err "python3 필요"
command -v curl      &>/dev/null || err "curl 필요"
command -v openssl   &>/dev/null || err "openssl 필요"
ok "사전 조건 OK"

# ══════════════════════════════════════════════════════════════════════
# SECTION 2 — 디렉토리 생성 (Phase 1 + 2 + 3)
# ══════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════
# SECTION 2.5 — Groq API Key (Multi-Agent)
# ══════════════════════════════════════════════════════════════════════
step "2.5/9  Groq API Key (Multi-Agent)"

echo ""
echo -e "${Y}  Multi-Agent 기능에 Groq API Key가 필요합니다.${N}"
echo "  https://console.groq.com → Settings → API Keys (무료)"
echo ""
while true; do
    read -t 120 -r -p "  Groq API Key (Enter=건너뜀): " GROQ_API_KEY || true
    GROQ_API_KEY=$(echo "$GROQ_API_KEY" | xargs 2>/dev/null || true)
    if [ -z "$GROQ_API_KEY" ]; then
        warn "Groq API Key 미입력 — Multi-Agent 비활성 상태로 설치"
        break
    fi
    if [ ${#GROQ_API_KEY} -ge 20 ]; then
        _GC=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer ${GROQ_API_KEY}" \
            "https://api.groq.com/openai/v1/models" 2>/dev/null || echo "000")
        [ "$_GC" = "200" ] && ok "Groq API Key 검증 성공" || warn "검증 실패 (HTTP ${_GC})"
        break
    fi
    warn "20자 이상 입력하세요."
done
if [ -n "$GROQ_API_KEY" ]; then
    if ! grep -q "^GROQ_API_KEY=" "$ENV_FILE" 2>/dev/null; then
        echo "GROQ_API_KEY=${GROQ_API_KEY}" >> "$ENV_FILE"
    else
        python3 -c "
import re,sys
k,v,p='GROQ_API_KEY',sys.argv[1],sys.argv[2]
with open(p) as f: c=f.read()
c=re.sub(r'^'+re.escape(k)+r'=.*',k+'='+v,c,flags=re.MULTILINE)
with open(p,'w') as f: f.write(c)
" "$GROQ_API_KEY" "$ENV_FILE"
    fi
    ok "GROQ_API_KEY → .env 저장"
fi

step "3/9  디렉토리 구조 생성"

# ── Phase 1: browser-agent ────────────────────────────────────────────
# 이전 실행에서 uid 1001 소유로 남은 파일/디렉토리 소유권 먼저 복구
if [ -d "${AGENT_DIR}" ]; then
    sudo chown -R "$(id -u):$(id -g)" "${AGENT_DIR}" 2>/dev/null || true
fi

mkdir -p "${AGENT_DIR}/data/screenshots" "${AGENT_DIR}/data/sessions" \
         "${AGENT_DIR}/data/results"     "${AGENT_DIR}/data/audit" \
         "${SECRETS_DIR}"
chmod 750 "${AGENT_DIR}"

# API 키를 secrets 파일에 저장 (컨테이너 :ro 마운트용)
echo -n "$BROWSER_API_KEY" > "${SECRETS_DIR}/api_key"
chmod 640 "${SECRETS_DIR}/api_key"
chmod 750 "${AGENT_DIR}/data" 2>/dev/null || true
find "${AGENT_DIR}/data" -type d -exec chmod 750 {} \; 2>/dev/null || true

# [FIX-06] 컨테이너 uid=1001 에 맞게 소유권 재설정
if ! sudo chown -R 1001:1001 "${AGENT_DIR}/data" "${SECRETS_DIR}" 2>/dev/null; then
    warn "sudo 사용 불가 — 컨테이너 접근을 위해 chmod 허용 범위 확대"
    chmod -R 775 "${AGENT_DIR}/data" 2>/dev/null || true
    chmod 644 "${SECRETS_DIR}/api_key" 2>/dev/null || true
    chmod 755 "${SECRETS_DIR}" 2>/dev/null || true
fi

ok "Phase 1 browser-agent 디렉토리 생성 (chmod 750, uid 1001)"

# ── Phase 2: tools-api ────────────────────────────────────────────────
mkdir -p "${TOOLS_API_DIR}/data"
chmod 750 "${TOOLS_API_DIR}"
ok "Phase 2 tools-api 디렉토리 생성"

# ── Phase 2: twilio-bot ───────────────────────────────────────────────
mkdir -p "${TWILIO_BOT_DIR}/data/recordings" \
         "${TWILIO_BOT_DIR}/data/reports"
chmod 750 "${TWILIO_BOT_DIR}"
# 이전 설치 잔여 권한 수정 (UID 1001 → 현재 사용자)
chown -R "$(id -u):$(id -g)" "${TWILIO_BOT_DIR}/data" 2>/dev/null || \
    sudo chown -R "$(id -u):$(id -g)" "${TWILIO_BOT_DIR}/data" 2>/dev/null || true
# 데이터 파일 초기화 (없을 경우만)
for F in contacts.json call_history.json schedules.json; do
    [ -f "${TWILIO_BOT_DIR}/data/${F}" ] || echo "[]" > "${TWILIO_BOT_DIR}/data/${F}"
done
ok "Phase 2 twilio-bot 디렉토리 생성"

# ── Phase 3: telegram-openwebui-bridge ───────────────────────────────
mkdir -p "${TELEGRAM_DIR}/bot" \
         "${TELEGRAM_DIR}/data" \
         "${TELEGRAM_DIR}/logs"
chmod 750 "${TELEGRAM_DIR}"
# ai-share 디렉토리 생성 (로컬 파일 공유용)
mkdir -p "${HOME}/ai-share"
ok "~/ai-share 디렉토리 생성 (로컬 파일 공유용)"

ok "Phase 3 telegram-openwebui-bridge 디렉토리 생성"

ok "전체 디렉토리 구조 생성 완료"
info "구조:"
info "  ~/OpenWebUI/browser-agent/  (Phase 1)"
info "  ~/OpenWebUI/tools-api/      (Phase 2)"
info "  ~/OpenWebUI/twilio-bot/     (Phase 2)"
info "  ~/telegram-openwebui-bridge/(Phase 3)"

# ══════════════════════════════════════════════════════════════════════
# SECTION 3 — 파일 생성
# ══════════════════════════════════════════════════════════════════════
step "4/9  컨테이너 파일 생성"

# ── FILE 1: Dockerfile ────────────────────────────────────────────────
cat > "${AGENT_DIR}/Dockerfile" << 'DOCKEREOF'
FROM python:3.12-slim-bookworm
LABEL maintainer="browser-use-agent"
LABEL version="6.1.0"
LABEL description="Browser Use Agent - CVE patched (2026-05)"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# [CVE-2026] 시스템 패키지 최소화 — VNC/Xvfb 완전 제거 (공격 표면 축소)
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    curl \
    netcat-openbsd \
    logrotate \
    fonts-dejavu-core \
    fonts-noto-cjk \
    # Playwright Chromium 의존성
    libnss3 libnspr4 libdbus-1-3 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 \
    libasound2 libatspi2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 1001 appuser \
    && useradd -u 1001 -g appuser -m -s /bin/bash appuser

# [CVE-FIX] 패키지 버전 고정 (2026-05 최신 보안 패치)
# [FIX] browser-use 먼저 설치 (의존성 자동 해결)
RUN pip install --no-cache-dir browser-use==0.12.6 && \
    pip install --no-cache-dir \
    langchain-groq==0.3.2 \
    langchain-openai==0.3.18 \
    langchain-anthropic==0.3.19 \
    langchain-google-genai==2.1.5 \
    fastapi==0.136.1 \
    uvicorn[standard]==0.46.0 \
    python-multipart==0.0.20 \
    python-jose[cryptography]==3.4.0 \
    passlib[bcrypt]==1.7.4 \
    bcrypt==4.3.0 \
    slowapi==0.1.9 \
    langgraph==0.4.7 \
    playwright==1.52.0

WORKDIR /app
COPY --chown=appuser:appuser . /app
RUN mkdir -p /app/multi_agent
RUN chmod +x /app/entrypoint.sh \
    && mkdir -p /app/data /app/secrets \
    && chown -R appuser:appuser /app/data /app/secrets

USER appuser
# Playwright Chromium 설치 (빌드 시 영구 포함)
RUN playwright install chromium

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8001/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
DOCKEREOF
ok "FILE 1/6  Dockerfile"

# ── FILE 2: .dockerignore ─────────────────────────────────────────────
cat > "${AGENT_DIR}/.dockerignore" << 'IGNOREEOF'
.git
.gitignore
.env
__pycache__
*.pyc
*.log
*.bak
*.tmp
*.swp
node_modules
.vscode
.idea
.DS_Store
*.snippet.yml
secrets/
data/
IGNOREEOF
ok "FILE 2/6  .dockerignore"

# ── FILE 3: entrypoint.sh ─────────────────────────────────────────────
cat > "${AGENT_DIR}/entrypoint.sh" << 'ENTRYEOF'
#!/bin/bash
set -euo pipefail

# 필수 디렉토리 생성
mkdir -p /app/data/audit /app/data/screenshots /app/data/sessions /app/data/results /app/logs 2>/dev/null || true

echo "============================================"
echo "  AI 브라우저 에이전트 v6.4.0"
echo "  (browser-agent-v5 → Browser Use 업그레이드)"
echo "============================================"
echo "Model: ${GROQ_MODEL:-llama-3.3-70b-versatile}"
echo "Port: 8001"
echo "Max Steps: ${MAX_STEPS_AGENT:-15}"
echo "Vision: ${USE_VISION:-false}"
echo "============================================"

echo "🤖 Browser Use Agent 서버 시작..."
exec python3 agent_server.py
ENTRYEOF
chmod +x "${AGENT_DIR}/entrypoint.sh"
ok "FILE 3/6  entrypoint.sh"

# ── FILE 4: agent_server.py (v6.4.0 — 전체수정반영) ──
AGENT_DIR="${AGENT_DIR}" python3 << 'WRITE_AGENT'
import base64, os
b64 = (
    "IiIiCkJyb3dzZXIgVXNlIEFnZW50IFNlcnZlciB2Ni4xLjAKYnJvd3Nlci1hZ2VudC12NSDihpIg"
    "QnJvd3NlciBVc2Ug7JeF6re466CI7J2065OcCkNWRSDrs7TslYgg7Yyo7LmYICsg66y07ZWc66Oo"
    "7ZSEIOuwqeyngCArIOuztOyViOqwle2ZlCAoMjAyNi0wNSkKIiIiCmltcG9ydCBhc3luY2lvLCBv"
    "cywganNvbiwgdGltZSwgbG9nZ2luZywgaGFzaGxpYiwgaG1hYywgc2VjcmV0cywgcmUgYXMgX3Jl"
    "CmZyb20gZGF0ZXRpbWUgaW1wb3J0IGRhdGV0aW1lCmZyb20gdHlwaW5nIGltcG9ydCBPcHRpb25h"
    "bApmcm9tIHBhdGhsaWIgaW1wb3J0IFBhdGgKZnJvbSBjb250ZXh0bGliIGltcG9ydCBhc3luY2Nv"
    "bnRleHRtYW5hZ2VyCmZyb20gdXJsbGliLnBhcnNlIGltcG9ydCB1cmxwYXJzZQoKZnJvbSBmYXN0"
    "YXBpIGltcG9ydCBGYXN0QVBJLCBIVFRQRXhjZXB0aW9uLCBSZXF1ZXN0LCBEZXBlbmRzCmZyb20g"
    "ZmFzdGFwaS5taWRkbGV3YXJlLmNvcnMgaW1wb3J0IENPUlNNaWRkbGV3YXJlCmZyb20gZmFzdGFw"
    "aS5taWRkbGV3YXJlLnRydXN0ZWRob3N0IGltcG9ydCBUcnVzdGVkSG9zdE1pZGRsZXdhcmUKZnJv"
    "bSBmYXN0YXBpLnJlc3BvbnNlcyBpbXBvcnQgSlNPTlJlc3BvbnNlCmZyb20gcHlkYW50aWMgaW1w"
    "b3J0IEJhc2VNb2RlbCwgRmllbGQsIGZpZWxkX3ZhbGlkYXRvcgpmcm9tIHNsb3dhcGkgaW1wb3J0"
    "IExpbWl0ZXIKZnJvbSBzbG93YXBpLnV0aWwgaW1wb3J0IGdldF9yZW1vdGVfYWRkcmVzcwpmcm9t"
    "IHNsb3dhcGkuZXJyb3JzIGltcG9ydCBSYXRlTGltaXRFeGNlZWRlZAoKZnJvbSBweWRhbnRpYyBp"
    "bXBvcnQgRmllbGQgYXMgUHlkYW50aWNGaWVsZAoKIyDilIDilIAg66mA7YuwIO2UhOuhnOuwlOyd"
    "tOuNlCBMTE0g7Yyp7Yag66asIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgAojIC5lbnYg65iQ64qUIEFQSSDtl6TrjZTroZwg7ZSE66Gc67CU7J20642UIOye"
    "kOuPmSDqsJDsp4AKIyDsp4Dsm5A6IEdyb3EsIE9wZW5BSSwgQW50aHJvcGljKENsYXVkZSksIEdv"
    "b2dsZShHZW1pbmkpCgpkZWYgX21ha2VfcHJvdmlkZXJfY2xhc3MoYmFzZV9jbHMsIHByb3ZpZGVy"
    "X25hbWUpOgogICAgIiIiYnJvd3Nlci11c2Ug7Zi47ZmYIOuemO2NvCDtgbTrnpjsiqQg7IOd7ISx"
    "IiIiCiAgICBjbGFzcyBXcmFwcGVkTExNKGJhc2VfY2xzKToKICAgICAgICBwcm92aWRlcjogc3Ry"
    "ID0gUHlkYW50aWNGaWVsZChkZWZhdWx0PXByb3ZpZGVyX25hbWUpCiAgICAgICAgbW9kZWw6IHN0"
    "ciA9IFB5ZGFudGljRmllbGQoZGVmYXVsdD0iIikKICAgICAgICBtb2RlbF9jb25maWcgPSB7ImV4"
    "dHJhIjogImFsbG93In0KICAgIFdyYXBwZWRMTE0uX19uYW1lX18gPSBmIntwcm92aWRlcl9uYW1l"
    "fUxMTSIKICAgIHJldHVybiBXcmFwcGVkTExNCgpkZWYgY3JlYXRlX2xsbShwcm92aWRlcj1Ob25l"
    "LCBhcGlfa2V5PU5vbmUsIG1vZGVsPU5vbmUsIHRlbXBlcmF0dXJlPTApOgogICAgIiIi7ZSE66Gc"
    "67CU7J20642U7JeQIOuUsOudvCBMTE0g7J247Iqk7YS07IqkIOyekOuPmSDsg53shLEiIiIKICAg"
    "ICMg7ZmY6rK967OA7IiY7JeQ7IScIOyekOuPmSDqsJDsp4AKICAgIGlmIG5vdCBwcm92aWRlcjoK"
    "ICAgICAgICBpZiBvcy5nZXRlbnYoIk9QRU5BSV9BUElfS0VZIikgb3IgKGFwaV9rZXkgYW5kIGFw"
    "aV9rZXkuc3RhcnRzd2l0aCgic2stIikgYW5kIG5vdCBhcGlfa2V5LnN0YXJ0c3dpdGgoInNrLWFu"
    "dC0iKSk6CiAgICAgICAgICAgIHByb3ZpZGVyID0gIm9wZW5haSIKICAgICAgICBlbGlmIG9zLmdl"
    "dGVudigiQU5USFJPUElDX0FQSV9LRVkiKSBvciAoYXBpX2tleSBhbmQgYXBpX2tleS5zdGFydHN3"
    "aXRoKCJzay1hbnQtIikpOgogICAgICAgICAgICBwcm92aWRlciA9ICJhbnRocm9waWMiCiAgICAg"
    "ICAgZWxpZiBvcy5nZXRlbnYoIkdPT0dMRV9BUElfS0VZIik6CiAgICAgICAgICAgIHByb3ZpZGVy"
    "ID0gImdvb2dsZSIKICAgICAgICBlbHNlOgogICAgICAgICAgICBwcm92aWRlciA9ICJncm9xIgoK"
    "ICAgIHByb3ZpZGVyID0gcHJvdmlkZXIubG93ZXIoKS5zdHJpcCgpCgogICAgaWYgcHJvdmlkZXIg"
    "PT0gIm9wZW5haSI6CiAgICAgICAgZnJvbSBsYW5nY2hhaW5fb3BlbmFpIGltcG9ydCBDaGF0T3Bl"
    "bkFJCiAgICAgICAgTExNQ2xhc3MgPSBfbWFrZV9wcm92aWRlcl9jbGFzcyhDaGF0T3BlbkFJLCAi"
    "b3BlbmFpIikKICAgICAgICBrZXkgPSBhcGlfa2V5IG9yIG9zLmdldGVudigiT1BFTkFJX0FQSV9L"
    "RVkiLCAiIikKICAgICAgICBtZGwgPSBtb2RlbCBvciBvcy5nZXRlbnYoIk9QRU5BSV9NT0RFTCIs"
    "ICJncHQtNG8iKQogICAgICAgIHJldHVybiBMTE1DbGFzcyhtb2RlbD1tZGwsIGFwaV9rZXk9a2V5"
    "LCB0ZW1wZXJhdHVyZT10ZW1wZXJhdHVyZSkKCiAgICBlbGlmIHByb3ZpZGVyIGluICgiYW50aHJv"
    "cGljIiwgImNsYXVkZSIpOgogICAgICAgIGZyb20gbGFuZ2NoYWluX2FudGhyb3BpYyBpbXBvcnQg"
    "Q2hhdEFudGhyb3BpYwogICAgICAgIExMTUNsYXNzID0gX21ha2VfcHJvdmlkZXJfY2xhc3MoQ2hh"
    "dEFudGhyb3BpYywgImFudGhyb3BpYyIpCiAgICAgICAga2V5ID0gYXBpX2tleSBvciBvcy5nZXRl"
    "bnYoIkFOVEhST1BJQ19BUElfS0VZIiwgIiIpCiAgICAgICAgbWRsID0gbW9kZWwgb3Igb3MuZ2V0"
    "ZW52KCJBTlRIUk9QSUNfTU9ERUwiLCAiY2xhdWRlLXNvbm5ldC00LTIwMjUwNTE0IikKICAgICAg"
    "ICByZXR1cm4gTExNQ2xhc3MobW9kZWw9bWRsLCBhcGlfa2V5PWtleSwgdGVtcGVyYXR1cmU9dGVt"
    "cGVyYXR1cmUpCgogICAgZWxpZiBwcm92aWRlciBpbiAoImdvb2dsZSIsICJnZW1pbmkiKToKICAg"
    "ICAgICBmcm9tIGxhbmdjaGFpbl9nb29nbGVfZ2VuYWkgaW1wb3J0IENoYXRHb29nbGVHZW5lcmF0"
    "aXZlQUkKICAgICAgICBMTE1DbGFzcyA9IF9tYWtlX3Byb3ZpZGVyX2NsYXNzKENoYXRHb29nbGVH"
    "ZW5lcmF0aXZlQUksICJnb29nbGUiKQogICAgICAgIGtleSA9IGFwaV9rZXkgb3Igb3MuZ2V0ZW52"
    "KCJHT09HTEVfQVBJX0tFWSIsICIiKQogICAgICAgIG1kbCA9IG1vZGVsIG9yIG9zLmdldGVudigi"
    "R09PR0xFX01PREVMIiwgImdlbWluaS0yLjUtZmxhc2giKQogICAgICAgIHJldHVybiBMTE1DbGFz"
    "cyhtb2RlbD1tZGwsIGdvb2dsZV9hcGlfa2V5PWtleSwgdGVtcGVyYXR1cmU9dGVtcGVyYXR1cmUp"
    "CgogICAgZWxzZTogICMgZ3JvcSAo6riw67O4KQogICAgICAgIGZyb20gbGFuZ2NoYWluX2dyb3Eg"
    "aW1wb3J0IENoYXRHcm9xCiAgICAgICAgTExNQ2xhc3MgPSBfbWFrZV9wcm92aWRlcl9jbGFzcyhD"
    "aGF0R3JvcSwgImdyb3EiKQogICAgICAgIGtleSA9IGFwaV9rZXkgb3Igb3MuZ2V0ZW52KCJHUk9R"
    "X0FQSV9LRVkiLCAiIikKICAgICAgICBtZGwgPSBtb2RlbCBvciBvcy5nZXRlbnYoIkdST1FfTU9E"
    "RUwiLCAibGxhbWEtMy4zLTcwYi12ZXJzYXRpbGUiKQogICAgICAgIHJldHVybiBMTE1DbGFzcyht"
    "b2RlbF9uYW1lPW1kbCwgYXBpX2tleT1rZXksIHRlbXBlcmF0dXJlPXRlbXBlcmF0dXJlLCBtYXhf"
    "cmV0cmllcz0zKQpmcm9tIGJyb3dzZXJfdXNlIGltcG9ydCBBZ2VudCwgQnJvd3NlclNlc3Npb24K"
    "ZnJvbSBicm93c2VyX3VzZS5icm93c2VyIGltcG9ydCBCcm93c2VyUHJvZmlsZQoKIyDilIDilIAg"
    "66Gc6rmFIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgApsb2dnaW5nLmJhc2ljQ29uZmlnKGxldmVsPWxvZ2dpbmcuSU5GTywKICAgIGZvcm1h"
    "dD0iJShhc2N0aW1lKXMgWyUobGV2ZWxuYW1lKXNdICUobWVzc2FnZSlzIikKbG9nZ2VyID0gbG9n"
    "Z2luZy5nZXRMb2dnZXIoImJyb3dzZXItdXNlLWFnZW50IikKCmF1ZGl0X2xvZ2dlciA9IGxvZ2dp"
    "bmcuZ2V0TG9nZ2VyKCJhdWRpdCIpCl9haCA9IGxvZ2dpbmcuRmlsZUhhbmRsZXIoIi9hcHAvZGF0"
    "YS9hdWRpdC9hZ2VudC5sb2ciKQpfYWguc2V0Rm9ybWF0dGVyKGxvZ2dpbmcuRm9ybWF0dGVyKCIl"
    "KGFzY3RpbWUpc3wlKG1lc3NhZ2UpcyIpKQphdWRpdF9sb2dnZXIuYWRkSGFuZGxlcihfYWgpCmF1"
    "ZGl0X2xvZ2dlci5zZXRMZXZlbChsb2dnaW5nLklORk8pCgojIOKUgOKUgCDtmZjqsr3rs4DsiJgg"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACkdST1FfQVBJX0tF"
    "WSA9IG9zLmdldGVudigiR1JPUV9BUElfS0VZIiwgIiIpCkdST1FfTU9ERUwgPSBvcy5nZXRlbnYo"
    "IkdST1FfTU9ERUwiLCAibGxhbWEtMy4zLTcwYi12ZXJzYXRpbGUiKQpMTE1fUFJPVklERVIgPSBv"
    "cy5nZXRlbnYoIkxMTV9QUk9WSURFUiIsICIiKSAgIyBhdXRvLWRldGVjdCBpZiBlbXB0eQpNQVhf"
    "U1RFUFMgPSBpbnQob3MuZ2V0ZW52KCJNQVhfU1RFUFNfQUdFTlQiLCAiMTUiKSkKVVNFX1ZJU0lP"
    "TiA9IG9zLmdldGVudigiVVNFX1ZJU0lPTiIsICJmYWxzZSIpLmxvd2VyKCkgPT0gInRydWUiCkFQ"
    "SV9LRVkgPSBvcy5nZXRlbnYoIkJST1dTRVJfQUdFTlRfQVBJX0tFWSIsICIiKQpJTlRFUk5BTF9U"
    "T0tFTiA9IG9zLmdldGVudigiQlJPV1NFUl9JTlRFUk5BTF9UT0tFTiIsICIiKQoKIyBbU0VDVVJJ"
    "VFldIO2DgOyehOyVhOybgyDshKTsoJUgKOustO2VnOujqO2UhCDrsKnsp4ApClRBU0tfVElNRU9V"
    "VCA9IGludChvcy5nZXRlbnYoIlRBU0tfVElNRU9VVCIsICIxODAiKSkgICAgICAgIyDri6jsnbwg"
    "7J6R7JeFIOy1nOuMgCAxODDstIgKTVVMVElfVElNRU9VVCA9IGludChvcy5nZXRlbnYoIk1VTFRJ"
    "X1RJTUVPVVQiLCAiMzAwIikpICAgICAjIE11bHRpLUFnZW50IOy1nOuMgCAzMDDstIgKU1RFUF9U"
    "SU1FT1VUID0gaW50KG9zLmdldGVudigiU1RFUF9USU1FT1VUIiwgIjMwIikpICAgICAgICAjIOuL"
    "qOydvCDsiqTthZ0g7LWc64yAIDMw7LSICgojIFtTRUNVUklUWV0g7ZeI7JqpIOuPhOuplOyduCAo"
    "67mI6rCSID0g7KCE7LK0IO2XiOyaqSkKQUxMT1dFRF9PUklHSU5TID0gb3MuZ2V0ZW52KCJBTExP"
    "V0VEX09SSUdJTlMiLCAiIikuc3BsaXQoIiwiKQpBTExPV0VEX09SSUdJTlMgPSBbby5zdHJpcCgp"
    "IGZvciBvIGluIEFMTE9XRURfT1JJR0lOUyBpZiBvLnN0cmlwKCldCgojIFtTRUNVUklUWV0g7LCo"
    "64uoIFVSTCDtjKjthLQKQkxPQ0tFRF9VUkxfUEFUVEVSTlMgPSBbCiAgICByIl5maWxlOi8vIiwg"
    "ciJeamF2YXNjcmlwdDoiLCByIl5kYXRhOiIsCiAgICByIl5mdHA6Ly8iLCByIl5jaHJvbWU6Ly8i"
    "LCByIl5hYm91dDoiLAogICAgciJsb2NhbGhvc3Q6XGQrL2FkbWluIiwgciIxMjdcLjBcLjBcLjEi"
    "LAogICAgciIxNjlcLjI1NFwuIiwgciIxMFwuXGQrXC5cZCtcLlxkKyIsICAjIOuCtOu2gCDrhKTt"
    "irjsm4ztgawKICAgIHIiMTkyXC4xNjhcLiIsIHIiMTcyXC4oMVs2LTldfDJcZHwzWzAxXSlcLiIs"
    "Cl0KCiMg4pSA4pSAIFJhdGUgTGltaXRlciDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIAKbGltaXRlciA9IExpbWl0ZXIoa2V5X2Z1bmM9Z2V0X3JlbW90ZV9hZGRyZXNzKQoKIyDilIDi"
    "lIAgTExNIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgApsbG0gPSBOb25lCgpkZWYgX2xvYWRfYXBpX2tleSgpOgogICAgaWYgQVBJX0tF"
    "WTogcmV0dXJuIEFQSV9LRVkKICAgIHRyeToKICAgICAgICBwID0gUGF0aCgiL2FwcC9zZWNyZXRz"
    "L2FwaV9rZXkiKQogICAgICAgIGlmIHAuZXhpc3RzKCk6IHJldHVybiBwLnJlYWRfdGV4dCgpLnN0"
    "cmlwKCkKICAgIGV4Y2VwdCBFeGNlcHRpb246IHBhc3MKICAgIHJldHVybiAiIgoKIyBbU0VDVVJJ"
    "VFldIOyDgeyImCDsi5zqsIQg67mE6rWQ66GcIO2DgOydtOuwjSDqs7Xqsqkg67Cp7KeACmRlZiB2"
    "ZXJpZnlfYXBpX2tleShyZXF1ZXN0OiBSZXF1ZXN0KToKICAgIGF1dGggPSByZXF1ZXN0LmhlYWRl"
    "cnMuZ2V0KCJBdXRob3JpemF0aW9uIiwgIiIpCiAgICBrZXkgPSBfbG9hZF9hcGlfa2V5KCkKICAg"
    "IGlmIG5vdCBrZXk6IHJldHVybiBUcnVlCiAgICB0b2tlbiA9IGF1dGgucmVwbGFjZSgiQmVhcmVy"
    "ICIsICIiKS5zdHJpcCgpCiAgICBpZiBub3QgdG9rZW46CiAgICAgICAgYXVkaXRfbG9nZ2VyLmlu"
    "Zm8oZiJBVVRIX01JU1NJTkd8e3JlcXVlc3QuY2xpZW50Lmhvc3R9fHtyZXF1ZXN0LnVybC5wYXRo"
    "fSIpCiAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbihzdGF0dXNfY29kZT00MDEsIGRldGFpbD0i"
    "QXV0aG9yaXphdGlvbiByZXF1aXJlZCIpCiAgICBpZiBub3QgaG1hYy5jb21wYXJlX2RpZ2VzdCh0"
    "b2tlbi5lbmNvZGUoKSwga2V5LmVuY29kZSgpKToKICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbyhm"
    "IkFVVEhfRkFJTHx7cmVxdWVzdC5jbGllbnQuaG9zdH18e3JlcXVlc3QudXJsLnBhdGh9IikKICAg"
    "ICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKHN0YXR1c19jb2RlPTQwMywgZGV0YWlsPSJJbnZhbGlk"
    "IEFQSSBrZXkiKQogICAgcmV0dXJuIFRydWUKCiMgW1NFQ1VSSVRZXSBVUkwg6rKA7KadCmRlZiB2"
    "YWxpZGF0ZV91cmwodXJsOiBzdHIpIC0+IGJvb2w6CiAgICBpZiBub3QgdXJsOiByZXR1cm4gVHJ1"
    "ZQogICAgdHJ5OgogICAgICAgIHBhcnNlZCA9IHVybHBhcnNlKHVybCkKICAgICAgICBpZiBwYXJz"
    "ZWQuc2NoZW1lIG5vdCBpbiAoImh0dHAiLCAiaHR0cHMiLCAiIik6CiAgICAgICAgICAgIHJldHVy"
    "biBGYWxzZQogICAgICAgIGZvciBwYXR0ZXJuIGluIEJMT0NLRURfVVJMX1BBVFRFUk5TOgogICAg"
    "ICAgICAgICBpZiBfcmUuc2VhcmNoKHBhdHRlcm4sIHVybCwgX3JlLklHTk9SRUNBU0UpOgogICAg"
    "ICAgICAgICAgICAgcmV0dXJuIEZhbHNlCiAgICAgICAgcmV0dXJuIFRydWUKICAgIGV4Y2VwdCBF"
    "eGNlcHRpb246CiAgICAgICAgcmV0dXJuIEZhbHNlCgojIFtTRUNVUklUWV0g7J6F66ClIOyDiOuL"
    "iO2DgOydtOynlQpkZWYgc2FuaXRpemVfdGFzayh0YXNrOiBzdHIpIC0+IHN0cjoKICAgICMg7KCc"
    "7Ja0IOusuOyekCDsoJzqsbAKICAgIHRhc2sgPSAiIi5qb2luKGMgZm9yIGMgaW4gdGFzayBpZiBj"
    "LmlzcHJpbnRhYmxlKCkgb3IgYyBpbiAiXG5cdCIpCiAgICAjIO2UhOuhrO2UhO2KuCDsnbjsoJ3s"
    "hZgg7Yyo7YS0IOqyveqzoAogICAgaW5qZWN0aW9uX3BhdHRlcm5zID0gWwogICAgICAgICJpZ25v"
    "cmUgcHJldmlvdXMiLCAiaWdub3JlIGFib3ZlIiwgImRpc3JlZ2FyZCIsCiAgICAgICAgInN5c3Rl"
    "bSBwcm9tcHQiLCAieW91IGFyZSBub3ciLCAibmV3IGluc3RydWN0aW9ucyIsCiAgICAgICAgImZv"
    "cmdldCBldmVyeXRoaW5nIiwgIm92ZXJyaWRlIiwgImphaWxicmVhayIsCiAgICBdCiAgICB0YXNr"
    "X2xvd2VyID0gdGFzay5sb3dlcigpCiAgICBmb3IgcCBpbiBpbmplY3Rpb25fcGF0dGVybnM6CiAg"
    "ICAgICAgaWYgcCBpbiB0YXNrX2xvd2VyOgogICAgICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbyhm"
    "IklOSkVDVElPTl9BVFRFTVBUfHtwfXx7dGFza1s6MTAwXX0iKQogICAgICAgICAgICBicmVhawog"
    "ICAgcmV0dXJuIHRhc2suc3RyaXAoKQoKCiMgW05BVkVSLVBSSU9SSVRZXSDtlZzqta3slrQg6rCQ"
    "7KeAICsg64Sk7J2067KEIOyasOyEoCDqsoDsg4kg66Gc7KeBCktPUkVBTl9TRUFSQ0hfUEFUVEVS"
    "TlMgPSB7CiAgICAi64Kg7JSoIjogImh0dHBzOi8vc2VhcmNoLm5hdmVyLmNvbS9zZWFyY2gubmF2"
    "ZXI/cXVlcnk9e3F9K+uCoOyUqCIsCiAgICAi7KO86rCAIjogImh0dHBzOi8vc2VhcmNoLm5hdmVy"
    "LmNvbS9zZWFyY2gubmF2ZXI/cXVlcnk9e3F9K+yjvOqwgCIsCiAgICAi7ZmY7JyoIjogImh0dHBz"
    "Oi8vc2VhcmNoLm5hdmVyLmNvbS9zZWFyY2gubmF2ZXI/cXVlcnk9e3F9K+2ZmOycqCIsCiAgICAi"
    "64m07IqkIjogImh0dHBzOi8vbmV3cy5uYXZlci5jb20iLAogICAgIuqwgOqyqSI6ICJodHRwczov"
    "L3NlYXJjaC5uYXZlci5jb20vc2VhcmNoLm5hdmVyP3F1ZXJ5PXtxfSvqsIDqsqkiLAp9CgpkZWYg"
    "ZGV0ZWN0X2tvcmVhbih0ZXh0OiBzdHIpIC0+IGJvb2w6CiAgICAiIiLtlZzqta3slrQg7Y+s7ZWo"
    "IOyXrOu2gCDqsJDsp4AiIiIKICAgIHJldHVybiBhbnkoMHhBQzAwIDw9IG9yZChjKSA8PSAweEQ3"
    "QTMgb3IgMHgzMTMxIDw9IG9yZChjKSA8PSAweDMxOEUgZm9yIGMgaW4gdGV4dCkKCmRlZiBhcHBs"
    "eV9uYXZlcl9wcmlvcml0eSh0YXNrOiBzdHIpIC0+IHN0cjoKICAgICIiIu2VnOq1reyWtCDsnpHs"
    "l4Xsl5Ag64Sk7J2067KEIOyasOyEoCDqsoDsg4kg7KeA7IucIOy2lOqwgCIiIgogICAgaWYgbm90"
    "IGRldGVjdF9rb3JlYW4odGFzayk6CiAgICAgICAgcmV0dXJuIHRhc2sKICAgIAogICAgIyDsnbTr"
    "r7ggVVJM7J20IO2PrO2VqOuQnCDqsr3smrAg6rG065Oc66as7KeAIOyViuydjAogICAgaWYgImh0"
    "dHA6Ly8iIGluIHRhc2sgb3IgImh0dHBzOi8vIiBpbiB0YXNrOgogICAgICAgIHJldHVybiB0YXNr"
    "CiAgICAKICAgICMg7Yq57KCVIO2CpOybjOuTnCDrp6Tsua0g4oaSIOuEpOydtOuyhCBVUkwg7J6Q"
    "64+ZIOyCveyehQogICAgdGFza19sb3dlciA9IHRhc2subG93ZXIoKQogICAgZm9yIGtleXdvcmQs"
    "IHVybF90ZW1wbGF0ZSBpbiBLT1JFQU5fU0VBUkNIX1BBVFRFUk5TLml0ZW1zKCk6CiAgICAgICAg"
    "aWYga2V5d29yZCBpbiB0YXNrOgogICAgICAgICAgICAjIO2CpOybjOuTnCDslZ7rkqQg7Luo7YWN"
    "7Iqk7Yq4IOy2lOy2nCAo7JiIOiAi7ISc7Jq4IOuCoOyUqCIg4oaSIHE9IuyEnOyauCIpCiAgICAg"
    "ICAgICAgIGltcG9ydCB1cmxsaWIucGFyc2UKICAgICAgICAgICAgcSA9IHRhc2sucmVwbGFjZShr"
    "ZXl3b3JkLCAiIikucmVwbGFjZSgi7JWM66Ck7KSYIiwiIikucmVwbGFjZSgi7ZmV7J24IiwiIiku"
    "cmVwbGFjZSgi6rKA7IOJIiwiIikuc3RyaXAoKQogICAgICAgICAgICBpZiBub3QgcTogcSA9IHRh"
    "c2sucmVwbGFjZShrZXl3b3JkLCIiKS5zdHJpcCgpIG9yIGtleXdvcmQKICAgICAgICAgICAgdXJs"
    "ID0gdXJsX3RlbXBsYXRlLmZvcm1hdChxPXVybGxpYi5wYXJzZS5xdW90ZShxKSkKICAgICAgICAg"
    "ICAgcmV0dXJuIGYiR28gdG8ge3VybH0gYW5kIHt0YXNrfS4gUmVzcG9uZCBpbiBLb3JlYW4uIgog"
    "ICAgCiAgICAjIOydvOuwmCDtlZzqta3slrQg7L+866asIOKGkiDrhKTsnbTrsoQg6rKA7IOJIOya"
    "sOyEoAogICAgcmV0dXJuIGYiU2VhcmNoIG9uIE5hdmVyIChodHRwczovL3NlYXJjaC5uYXZlci5j"
    "b20pIGZpcnN0IGZvcjoge3Rhc2t9LiBJZiBOYXZlciBkb2Vzbid0IGhhdmUgdGhlIGFuc3dlciwg"
    "dHJ5IEdvb2dsZS4gQWx3YXlzIHJlc3BvbmQgaW4gS29yZWFuLiIKCiMgW1NFQ1VSSVRZXSDrj5ns"
    "i5wg7Iuk7ZaJIOygnO2VnApfYWN0aXZlX3Rhc2tzID0gMApfYWN0aXZlX2xvY2sgPSBhc3luY2lv"
    "LkxvY2soKQpNQVhfQ09OQ1VSUkVOVCA9IGludChvcy5nZXRlbnYoIk1BWF9DT05DVVJSRU5UIiwg"
    "IjMiKSkKCkBhc3luY2NvbnRleHRtYW5hZ2VyCmFzeW5jIGRlZiB0YXNrX3Nsb3QoKToKICAgIGds"
    "b2JhbCBfYWN0aXZlX3Rhc2tzCiAgICBhc3luYyB3aXRoIF9hY3RpdmVfbG9jazoKICAgICAgICBp"
    "ZiBfYWN0aXZlX3Rhc2tzID49IE1BWF9DT05DVVJSRU5UOgogICAgICAgICAgICByYWlzZSBIVFRQ"
    "RXhjZXB0aW9uKDQyOSwgZiJUb28gbWFueSBjb25jdXJyZW50IHRhc2tzICh7TUFYX0NPTkNVUlJF"
    "TlR9IG1heCkiKQogICAgICAgIF9hY3RpdmVfdGFza3MgKz0gMQogICAgdHJ5OgogICAgICAgIHlp"
    "ZWxkCiAgICBmaW5hbGx5OgogICAgICAgIGFzeW5jIHdpdGggX2FjdGl2ZV9sb2NrOgogICAgICAg"
    "ICAgICBfYWN0aXZlX3Rhc2tzIC09IDEKCkBhc3luY2NvbnRleHRtYW5hZ2VyCmFzeW5jIGRlZiBs"
    "aWZlc3BhbihhcHA6IEZhc3RBUEkpOgogICAgZ2xvYmFsIGxsbQogICAgIyDrqYDti7Ag7ZSE66Gc"
    "67CU7J20642UIOyekOuPmSDqsJDsp4AKICAgIHRyeToKICAgICAgICBsbG0gPSBjcmVhdGVfbGxt"
    "KHByb3ZpZGVyPUxMTV9QUk9WSURFUikKICAgICAgICBsb2dnZXIuaW5mbyhmIkxMTSBpbml0OiBw"
    "cm92aWRlcj17bGxtLnByb3ZpZGVyfSwgbW9kZWw9e2dldGF0dHIobGxtLCAnbW9kZWxfbmFtZScs"
    "IGdldGF0dHIobGxtLCAnbW9kZWwnLCAndW5rbm93bicpKX0iKQogICAgZXhjZXB0IEV4Y2VwdGlv"
    "biBhcyBlOgogICAgICAgIGxvZ2dlci5lcnJvcihmIkxMTSBpbml0IGZhaWxlZDoge2V9IikKICAg"
    "ICAgICBsb2dnZXIuZXJyb3IoIlNldCBhdCBsZWFzdCBvbmUgQVBJIGtleTogR1JPUV9BUElfS0VZ"
    "LCBPUEVOQUlfQVBJX0tFWSwgQU5USFJPUElDX0FQSV9LRVksIG9yIEdPT0dMRV9BUElfS0VZIikK"
    "ICAgIGxvZ2dlci5pbmZvKGYiVGltZW91dHM6IHRhc2s9e1RBU0tfVElNRU9VVH1zIG11bHRpPXtN"
    "VUxUSV9USU1FT1VUfXMgc3RlcD17U1RFUF9USU1FT1VUfXMiKQogICAgbG9nZ2VyLmluZm8oZiJD"
    "b25jdXJyZW5jeSBsaW1pdDoge01BWF9DT05DVVJSRU5UfSIpCiAgICB5aWVsZAoKYXBwID0gRmFz"
    "dEFQSSh0aXRsZT0iQnJvd3NlciBVc2UgQWdlbnQiLCB2ZXJzaW9uPSI2LjIuMCIsIGxpZmVzcGFu"
    "PWxpZmVzcGFuLAogICAgICAgICAgICAgIGRvY3NfdXJsPU5vbmUsIHJlZG9jX3VybD1Ob25lKSAg"
    "IyBbU0VDVVJJVFldIFN3YWdnZXIgVUkg67mE7Zmc7ISx7ZmUCmFwcC5zdGF0ZS5saW1pdGVyID0g"
    "bGltaXRlcgoKQGFwcC5leGNlcHRpb25faGFuZGxlcihSYXRlTGltaXRFeGNlZWRlZCkKYXN5bmMg"
    "ZGVmIHJhdGVfbGltaXRfaGFuZGxlcihyZXF1ZXN0LCBleGMpOgogICAgYXVkaXRfbG9nZ2VyLmlu"
    "Zm8oZiJSQVRFX0xJTUlUfHtyZXF1ZXN0LmNsaWVudC5ob3N0fXx7cmVxdWVzdC51cmwucGF0aH0i"
    "KQogICAgcmV0dXJuIEpTT05SZXNwb25zZShzdGF0dXNfY29kZT00MjksIGNvbnRlbnQ9eyJlcnJv"
    "ciI6ICJSYXRlIGxpbWl0IGV4Y2VlZGVkIn0pCgojIFtTRUNVUklUWV0gQ09SUyDsoJztlZwKaWYg"
    "QUxMT1dFRF9PUklHSU5TOgogICAgYXBwLmFkZF9taWRkbGV3YXJlKENPUlNNaWRkbGV3YXJlLCBh"
    "bGxvd19vcmlnaW5zPUFMTE9XRURfT1JJR0lOUywKICAgICAgICBhbGxvd19tZXRob2RzPVsiR0VU"
    "IiwiUE9TVCJdLCBhbGxvd19oZWFkZXJzPVsiQXV0aG9yaXphdGlvbiIsIkNvbnRlbnQtVHlwZSJd"
    "KQplbHNlOgogICAgYXBwLmFkZF9taWRkbGV3YXJlKENPUlNNaWRkbGV3YXJlLCBhbGxvd19vcmln"
    "aW5zPVsiKiJdLAogICAgICAgIGFsbG93X21ldGhvZHM9WyJHRVQiLCJQT1NUIl0sIGFsbG93X2hl"
    "YWRlcnM9WyIqIl0pCgojIFtTRUNVUklUWV0g67O07JWIIO2XpOuNlCDrr7jrk6Tsm6jslrQKQGFw"
    "cC5taWRkbGV3YXJlKCJodHRwIikKYXN5bmMgZGVmIHNlY3VyaXR5X2hlYWRlcnMocmVxdWVzdDog"
    "UmVxdWVzdCwgY2FsbF9uZXh0KToKICAgICMgW1NFQ1VSSVRZXSDsmpTssq0g67O466y4IO2BrOq4"
    "sCDsoJztlZwgKDEwS0IpCiAgICBjb250ZW50X2xlbmd0aCA9IHJlcXVlc3QuaGVhZGVycy5nZXQo"
    "ImNvbnRlbnQtbGVuZ3RoIiwgIjAiKQogICAgaWYgaW50KGNvbnRlbnRfbGVuZ3RoKSA+IDEwMjQw"
    "OgogICAgICAgIHJldHVybiBKU09OUmVzcG9uc2Uoc3RhdHVzX2NvZGU9NDEzLCBjb250ZW50PXsi"
    "ZXJyb3IiOiAiUmVxdWVzdCB0b28gbGFyZ2UifSkKICAgIHJlc3BvbnNlID0gYXdhaXQgY2FsbF9u"
    "ZXh0KHJlcXVlc3QpCiAgICByZXNwb25zZS5oZWFkZXJzWyJYLUNvbnRlbnQtVHlwZS1PcHRpb25z"
    "Il0gPSAibm9zbmlmZiIKICAgIHJlc3BvbnNlLmhlYWRlcnNbIlgtRnJhbWUtT3B0aW9ucyJdID0g"
    "IkRFTlkiCiAgICByZXNwb25zZS5oZWFkZXJzWyJYLVhTUy1Qcm90ZWN0aW9uIl0gPSAiMTsgbW9k"
    "ZT1ibG9jayIKICAgIHJlc3BvbnNlLmhlYWRlcnNbIlJlZmVycmVyLVBvbGljeSJdID0gInN0cmlj"
    "dC1vcmlnaW4td2hlbi1jcm9zcy1vcmlnaW4iCiAgICByZXNwb25zZS5oZWFkZXJzWyJQZXJtaXNz"
    "aW9ucy1Qb2xpY3kiXSA9ICJjYW1lcmE9KCksIG1pY3JvcGhvbmU9KCksIGdlb2xvY2F0aW9uPSgp"
    "IgogICAgcmVzcG9uc2UuaGVhZGVyc1siQ29udGVudC1TZWN1cml0eS1Qb2xpY3kiXSA9ICJkZWZh"
    "dWx0LXNyYyAnbm9uZSc7IGZyYW1lLWFuY2VzdG9ycyAnbm9uZSciCiAgICByZXNwb25zZS5oZWFk"
    "ZXJzWyJDYWNoZS1Db250cm9sIl0gPSAibm8tc3RvcmUsIG5vLWNhY2hlLCBtdXN0LXJldmFsaWRh"
    "dGUiCiAgICByZXNwb25zZS5oZWFkZXJzWyJQcmFnbWEiXSA9ICJuby1jYWNoZSIKICAgIHJlc3Bv"
    "bnNlLmhlYWRlcnNbIlgtUmVxdWVzdC1JRCJdID0gc2VjcmV0cy50b2tlbl9oZXgoOCkKICAgIHJl"
    "dHVybiByZXNwb25zZQoKIyDilIDilIAg66qo6424IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApjbGFzcyBNdWx0aVRhYlJlcXVlc3QoQmFz"
    "ZU1vZGVsKToKICAgIHRhc2s6IHN0ciA9IEZpZWxkKC4uLiwgbWluX2xlbmd0aD0xLCBtYXhfbGVu"
    "Z3RoPTIwMDAsIGRlc2NyaXB0aW9uPSLruYTqtZAv67aE7ISd7ZWgIOyekeyXhSIpCiAgICB1cmxz"
    "OiBsaXN0W3N0cl0gPSBGaWVsZChkZWZhdWx0PVtdLCBtYXhfbGVuZ3RoPTUsIGRlc2NyaXB0aW9u"
    "PSLrsKnrrLjtlaAgVVJMIOuqqeuhnSAo7LWc64yAIDXqsJwpIikKICAgIG1heF9zdGVwc19wZXJf"
    "dGFiOiBpbnQgPSBGaWVsZChkZWZhdWx0PTgsIGdlPTEsIGxlPTE1KQogICAgcHJvdmlkZXI6IE9w"
    "dGlvbmFsW3N0cl0gPSBOb25lCiAgICBhcGlfa2V5OiBPcHRpb25hbFtzdHJdID0gTm9uZQogICAg"
    "bW9kZWw6IE9wdGlvbmFsW3N0cl0gPSBOb25lCgpjbGFzcyBCcm93c2VSZXF1ZXN0KEJhc2VNb2Rl"
    "bCk6CiAgICB0YXNrOiBzdHIgPSBGaWVsZCguLi4sIG1pbl9sZW5ndGg9MSwgbWF4X2xlbmd0aD0y"
    "MDAwKQogICAgdXJsOiBPcHRpb25hbFtzdHJdID0gRmllbGQoTm9uZSwgbWF4X2xlbmd0aD01MDAp"
    "CiAgICBtYXhfc3RlcHM6IE9wdGlvbmFsW2ludF0gPSBGaWVsZChOb25lLCBnZT0xLCBsZT0zMCkK"
    "ICAgIHVzZV92aXNpb246IE9wdGlvbmFsW2Jvb2xdID0gTm9uZQogICAgcHJvdmlkZXI6IE9wdGlv"
    "bmFsW3N0cl0gPSBGaWVsZChOb25lLCBkZXNjcmlwdGlvbj0iTExNIHByb3ZpZGVyOiBncm9xL29w"
    "ZW5haS9hbnRocm9waWMvZ29vZ2xlIikKICAgIGFwaV9rZXk6IE9wdGlvbmFsW3N0cl0gPSBGaWVs"
    "ZChOb25lLCBkZXNjcmlwdGlvbj0iT3ZlcnJpZGUgQVBJIGtleSIpCiAgICBtb2RlbDogT3B0aW9u"
    "YWxbc3RyXSA9IEZpZWxkKE5vbmUsIGRlc2NyaXB0aW9uPSJPdmVycmlkZSBtb2RlbCBuYW1lIikK"
    "CiAgICBAZmllbGRfdmFsaWRhdG9yKCJ1cmwiKQogICAgQGNsYXNzbWV0aG9kCiAgICBkZWYgY2hl"
    "Y2tfdXJsKGNscywgdik6CiAgICAgICAgaWYgdiBhbmQgbm90IHZhbGlkYXRlX3VybCh2KToKICAg"
    "ICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiVVJMIG5vdCBhbGxvd2VkIChibG9ja2VkIHNjaGVt"
    "ZSBvciBpbnRlcm5hbCBuZXR3b3JrKSIpCiAgICAgICAgcmV0dXJuIHYKCiAgICBAZmllbGRfdmFs"
    "aWRhdG9yKCJ0YXNrIikKICAgIEBjbGFzc21ldGhvZAogICAgZGVmIGNoZWNrX3Rhc2soY2xzLCB2"
    "KToKICAgICAgICByZXR1cm4gc2FuaXRpemVfdGFzayh2KQoKY2xhc3MgQnJvd3NlUmVzcG9uc2Uo"
    "QmFzZU1vZGVsKToKICAgIHN1Y2Nlc3M6IGJvb2wKICAgIHN1bW1hcnk6IE9wdGlvbmFsW3N0cl0g"
    "PSBOb25lCiAgICBzdW1tYXJ5X3BsYWluOiBPcHRpb25hbFtzdHJdID0gTm9uZQogICAgZXJyb3I6"
    "IE9wdGlvbmFsW3N0cl0gPSBOb25lCiAgICBzdGVwc190YWtlbjogaW50ID0gMAogICAgZWxhcHNl"
    "ZF9zZWM6IGZsb2F0ID0gMC4wCiAgICB0aW1lc3RhbXA6IHN0ciA9ICIiCgojIOKUgOKUgCDruIzr"
    "nbzsmrDsoIAg7Iuk7ZaJIO2XrO2NvCAo7YOA7J6E7JWE7JuDIO2PrO2VqCkg4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSACmFzeW5jIGRlZiBfcnVuX2FnZW50KHRhc2s6IHN0ciwgc3RlcHM6IGludCwg"
    "dmlzaW9uOiBib29sLCBvdmVycmlkZV9sbG09Tm9uZSkgLT4gZGljdDoKICAgIHNlc3Npb24gPSBO"
    "b25lCiAgICB0MCA9IHRpbWUudGltZSgpCiAgICB0cnk6CiAgICAgICAgc2Vzc2lvbiA9IEJyb3dz"
    "ZXJTZXNzaW9uKGJyb3dzZXJfcHJvZmlsZT1Ccm93c2VyUHJvZmlsZSgKICAgICAgICAgICAgaGVh"
    "ZGxlc3M9VHJ1ZSwgZGlzYWJsZV9zZWN1cml0eT1GYWxzZSwKICAgICAgICAgICAgdmlld3BvcnQ9"
    "eyJ3aWR0aCI6IDEyODAsICJoZWlnaHQiOiA3MjB9KSkKCiAgICAgICAgYWN0aXZlX2xsbSA9IG92"
    "ZXJyaWRlX2xsbSBvciBsbG0KICAgICAgICBhZ2VudCA9IEFnZW50KHRhc2s9dGFzaywgbGxtPWFj"
    "dGl2ZV9sbG0sIGJyb3dzZXJfc2Vzc2lvbj1zZXNzaW9uLAogICAgICAgICAgICAgICAgICAgICAg"
    "dXNlX3Zpc2lvbj12aXNpb24sIG1heF9hY3Rpb25zX3Blcl9zdGVwPTUpCgogICAgICAgICMgW0FO"
    "VEktTE9PUF0gYXN5bmNpby53YWl0X2ZvcuuhnCDsoITssrQg7YOA7J6E7JWE7JuDIOyggeyaqQog"
    "ICAgICAgIHJlc3VsdCA9IGF3YWl0IGFzeW5jaW8ud2FpdF9mb3IoCiAgICAgICAgICAgIGFnZW50"
    "LnJ1bihtYXhfc3RlcHM9c3RlcHMpLAogICAgICAgICAgICB0aW1lb3V0PVRBU0tfVElNRU9VVAog"
    "ICAgICAgICkKCiAgICAgICAgZmluYWwgPSByZXN1bHQuZmluYWxfcmVzdWx0KCkgaWYgcmVzdWx0"
    "IGVsc2UgImNvbXBsZXRlZCIKICAgICAgICBoaXN0b3J5ID0gcmVzdWx0Lmhpc3RvcnkgaWYgcmVz"
    "dWx0IGVsc2UgW10KICAgICAgICBuID0gbGVuKGhpc3RvcnkpIGlmIGhpc3RvcnkgZWxzZSAwCiAg"
    "ICAgICAgZWxhcHNlZCA9IHJvdW5kKHRpbWUudGltZSgpIC0gdDAsIDIpCgogICAgICAgIHJldHVy"
    "biB7InN1Y2Nlc3MiOiBUcnVlLCAic3VtbWFyeSI6IGZpbmFsLCAic3VtbWFyeV9wbGFpbiI6IGZp"
    "bmFsLAogICAgICAgICAgICAgICAgInN0ZXBzX3Rha2VuIjogbiwgImVsYXBzZWRfc2VjIjogZWxh"
    "cHNlZH0KCiAgICBleGNlcHQgYXN5bmNpby5UaW1lb3V0RXJyb3I6CiAgICAgICAgZWxhcHNlZCA9"
    "IHJvdW5kKHRpbWUudGltZSgpIC0gdDAsIDIpCiAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJU"
    "SU1FT1VUfHtlbGFwc2VkfXN8e3Rhc2tbOjgwXX0iKQogICAgICAgIHJldHVybiB7InN1Y2Nlc3Mi"
    "OiBGYWxzZSwKICAgICAgICAgICAgICAgICJlcnJvciI6IGYiVGFzayB0aW1lZCBvdXQgYWZ0ZXIg"
    "e1RBU0tfVElNRU9VVH1zICh7ZWxhcHNlZH1zIGVsYXBzZWQpIiwKICAgICAgICAgICAgICAgICJl"
    "bGFwc2VkX3NlYyI6IGVsYXBzZWR9CgogICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAg"
    "IGVsYXBzZWQgPSByb3VuZCh0aW1lLnRpbWUoKSAtIHQwLCAyKQogICAgICAgIHJldHVybiB7InN1"
    "Y2Nlc3MiOiBGYWxzZSwgImVycm9yIjogc3RyKGUpLCAiZWxhcHNlZF9zZWMiOiBlbGFwc2VkfQoK"
    "ICAgIGZpbmFsbHk6CiAgICAgICAgaWYgc2Vzc2lvbjoKICAgICAgICAgICAgdHJ5OiBhd2FpdCBh"
    "c3luY2lvLndhaXRfZm9yKHNlc3Npb24uY2xvc2UoKSwgdGltZW91dD01KQogICAgICAgICAgICBl"
    "eGNlcHQ6IHBhc3MKCgojIOKUgOKUgCDrqZTrqqjrpqwv7ZWZ7Iq1IOyLnOyKpO2FnCDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIAKaW1wb3J0IGpzb24gYXMgX2pzb24KZnJvbSBwYXRobGliIGltcG9ydCBQYXRoIGFz"
    "IF9QYXRoCgpNRU1PUllfRklMRSA9IF9QYXRoKCIvYXBwL2RhdGEvdXNlcl9tZW1vcnkuanNvbiIp"
    "CkFMTE9XRURfRklMRV9FWFQgPSB7Ii50eHQiLCIubWQiLCIuY3N2IiwiLmpzb24iLCIucGRmIiwi"
    "Lnhsc3giLCIueGxzIiwiLmRvY3giLCIuaHRtbCIsIi54bWwiLCIubG9nIiwiLnB5IiwiLnNoIn0K"
    "VVNFUl9GSUxFU19ESVIgPSBfUGF0aCgiL2FwcC9kYXRhL3VzZXJfZmlsZXMiKQoKZGVmIF9sb2Fk"
    "X21lbW9yeSgpIC0+IGRpY3Q6CiAgICB0cnk6CiAgICAgICAgaWYgTUVNT1JZX0ZJTEUuZXhpc3Rz"
    "KCk6CiAgICAgICAgICAgIHJldHVybiBfanNvbi5sb2FkcyhNRU1PUllfRklMRS5yZWFkX3RleHQo"
    "InV0Zi04IikpCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHBhc3MKICAgIHJldHVybiB7"
    "ImxvY2F0aW9uIjoiIiwiaW50ZXJlc3RzIjpbXSwicHJlZmVyZW5jZXMiOnt9LCJmYWN0cyI6W10s"
    "InBhc3RfcXVlcmllcyI6W119CgpkZWYgX3NhdmVfbWVtb3J5KG1lbTogZGljdCk6CiAgICB0cnk6"
    "CiAgICAgICAgTUVNT1JZX0ZJTEUucGFyZW50Lm1rZGlyKHBhcmVudHM9VHJ1ZSwgZXhpc3Rfb2s9"
    "VHJ1ZSkKICAgICAgICBNRU1PUllfRklMRS53cml0ZV90ZXh0KF9qc29uLmR1bXBzKG1lbSwgZW5z"
    "dXJlX2FzY2lpPUZhbHNlLCBpbmRlbnQ9MiksICJ1dGYtOCIpCiAgICBleGNlcHQgRXhjZXB0aW9u"
    "IGFzIGU6CiAgICAgICAgbG9nZ2VyLmVycm9yKGYiTWVtb3J5IHNhdmUgZmFpbGVkOiB7ZX0iKQoK"
    "ZGVmIF91cGRhdGVfbWVtb3J5X2Zyb21fdGFzayh0YXNrOiBzdHIsIHJlc3VsdDogc3RyKToKICAg"
    "ICIiIuyekeyXhSDquLDroZ3sl5DshJwg7J6Q64+Z7Jy866GcIOyCrOyaqeyekCDsoJXrs7Qg7ZWZ"
    "7Iq1IiIiCiAgICBtZW0gPSBfbG9hZF9tZW1vcnkoKQogICAgIyDstZzqt7wg7L+866asIOyggOye"
    "pSAo7LWc64yAIDUw6rCcKQogICAgbWVtWyJwYXN0X3F1ZXJpZXMiXSA9IG1lbS5nZXQoInBhc3Rf"
    "cXVlcmllcyIsIFtdKVstNDk6XSArIFsKICAgICAgICB7InRhc2siOiB0YXNrWzoyMDBdLCAidGlt"
    "ZSI6IGRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpfQogICAgXQogICAgIyDsnITsuZgg7J6Q64+Z"
    "IOqwkOyngAogICAgaW1wb3J0IHJlIGFzIF9yZTIKICAgIGxvY19tYXRjaCA9IF9yZTIuc2VhcmNo"
    "KHIiKOyEnOyauHzrtoDsgrB864yA6rWsfOyduOyynHzqtJHso7x864yA7KCEfOyauOyCsHzshLjs"
    "ooV87KCc7KO8fOyImOybkHzshLHrgqh86rOg7JaRKSIsIHRhc2spCiAgICBpZiBsb2NfbWF0Y2gg"
    "YW5kIG5vdCBtZW0uZ2V0KCJsb2NhdGlvbiIpOgogICAgICAgIG1lbVsibG9jYXRpb24iXSA9IGxv"
    "Y19tYXRjaC5ncm91cCgxKQogICAgIyDqtIDsi6zsgqwg7J6Q64+ZIOqwkOyngAogICAgaW50ZXJl"
    "c3Rfa2V5d29yZHMgPSB7IuyjvOqwgCI6IuyjvOyLnSIsIu2ZmOycqCI6Iuq4iOyctSIsIuuCoOyU"
    "qCI6IuuCoOyUqCIsIuuJtOyKpCI6IuuJtOyKpCIsCiAgICAgICAgICAgICAgICAgICAgICAgICAi"
    "6rCA6rKpIjoi7Ie87ZWRIiwi7ZWt6rO1Ijoi7Jes7ZaJIiwi66eb7KeRIjoi7J2M7IudIiwi67aA"
    "64+Z7IKwIjoi67aA64+Z7IKwIn0KICAgIGZvciBrdywgaW50ZXJlc3QgaW4gaW50ZXJlc3Rfa2V5"
    "d29yZHMuaXRlbXMoKToKICAgICAgICBpZiBrdyBpbiB0YXNrIGFuZCBpbnRlcmVzdCBub3QgaW4g"
    "bWVtLmdldCgiaW50ZXJlc3RzIixbXSk6CiAgICAgICAgICAgIG1lbS5zZXRkZWZhdWx0KCJpbnRl"
    "cmVzdHMiLFtdKS5hcHBlbmQoaW50ZXJlc3QpCiAgICAgICAgICAgIG1lbVsiaW50ZXJlc3RzIl0g"
    "PSBtZW1bImludGVyZXN0cyJdWy0yMDpdCiAgICBfc2F2ZV9tZW1vcnkobWVtKQoKZGVmIF9nZXRf"
    "bWVtb3J5X2NvbnRleHQoKSAtPiBzdHI6CiAgICAiIiJMTE0g7ZSE66Gs7ZSE7Yq47JeQIOyjvOye"
    "he2VoCDrqZTrqqjrpqwg7Luo7YWN7Iqk7Yq4IiIiCiAgICBtZW0gPSBfbG9hZF9tZW1vcnkoKQog"
    "ICAgcGFydHMgPSBbXQogICAgaWYgbWVtLmdldCgibG9jYXRpb24iKToKICAgICAgICBwYXJ0cy5h"
    "cHBlbmQoZiJVc2VyIGxvY2F0aW9uOiB7bWVtWydsb2NhdGlvbiddfSIpCiAgICBpZiBtZW0uZ2V0"
    "KCJpbnRlcmVzdHMiKToKICAgICAgICBwYXJ0cy5hcHBlbmQoZiJVc2VyIGludGVyZXN0czogeycs"
    "ICcuam9pbihtZW1bJ2ludGVyZXN0cyddWzoxMF0pfSIpCiAgICBpZiBtZW0uZ2V0KCJwcmVmZXJl"
    "bmNlcyIpOgogICAgICAgIHBhcnRzLmFwcGVuZChmIlByZWZlcmVuY2VzOiB7X2pzb24uZHVtcHMo"
    "bWVtWydwcmVmZXJlbmNlcyddLCBlbnN1cmVfYXNjaWk9RmFsc2UpfSIpCiAgICBpZiBtZW0uZ2V0"
    "KCJmYWN0cyIpOgogICAgICAgIHBhcnRzLmFwcGVuZChmIktub3duIGZhY3RzOiB7JzsgJy5qb2lu"
    "KG1lbVsnZmFjdHMnXVstNTpdKX0iKQogICAgcmV0dXJuICJcbiIuam9pbihwYXJ0cykgaWYgcGFy"
    "dHMgZWxzZSAiIgoKIyDilIDilIAg66Gc7LusIO2MjOydvCDsoJHqt7wg7Iuc7Iqk7YWcIOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gApkZWYgX3NhZmVfcGF0aChmaWxlbmFtZTogc3RyKSAtPiBfUGF0aDoKICAgICIiIuqyveuhnCDt"
    "g4jstpwg67Cp7KeAIiIiCiAgICBjbGVhbiA9IF9QYXRoKGZpbGVuYW1lKS5uYW1lICAjIOuUlOug"
    "ie2GoOumrCDtg5Dsg4kg7LCo64uoCiAgICBpZiAiLi4iIGluIHN0cihmaWxlbmFtZSkgb3IgIi8i"
    "IGluIGZpbGVuYW1lIG9yICJcXCIgaW4gZmlsZW5hbWU6CiAgICAgICAgcmFpc2UgVmFsdWVFcnJv"
    "cigiSW52YWxpZCBmaWxlbmFtZSIpCiAgICBwYXRoID0gVVNFUl9GSUxFU19ESVIgLyBjbGVhbgog"
    "ICAgaWYgbm90IHN0cihwYXRoLnJlc29sdmUoKSkuc3RhcnRzd2l0aChzdHIoVVNFUl9GSUxFU19E"
    "SVIucmVzb2x2ZSgpKSk6CiAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiUGF0aCB0cmF2ZXJzYWwg"
    "YmxvY2tlZCIpCiAgICBpZiBwYXRoLnN1ZmZpeC5sb3dlcigpIG5vdCBpbiBBTExPV0VEX0ZJTEVf"
    "RVhUOgogICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoZiJFeHRlbnNpb24gbm90IGFsbG93ZWQ6IHtw"
    "YXRoLnN1ZmZpeH0iKQogICAgcmV0dXJuIHBhdGgKCiMg4pSA4pSAIOyXlOuTnO2PrOyduO2KuCDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKQGFwcC5nZXQoIi9oZWFsdGgi"
    "KQpkZWYgaGVhbHRoKCk6CiAgICBtdWx0aV9vayA9IEZhbHNlCiAgICB0cnk6CiAgICAgICAgZnJv"
    "bSBtdWx0aV9hZ2VudC5ncmFwaCBpbXBvcnQgYnVpbGRfZ3JhcGgKICAgICAgICBtdWx0aV9vayA9"
    "IFRydWUKICAgIGV4Y2VwdCBFeGNlcHRpb246IHBhc3MKICAgIHJldHVybiB7InN0YXR1cyI6ICJo"
    "ZWFsdGh5IiBpZiBsbG0gZWxzZSAibm9fYXBpX2tleSIsCiAgICAgICAgICAgICJtb2RlbCI6IEdS"
    "T1FfTU9ERUwsICJ2ZXJzaW9uIjogIjYuMS4wIiwKICAgICAgICAgICAgImVuZ2luZSI6ICJicm93"
    "c2VyLXVzZSIsCiAgICAgICAgICAgICJtdWx0aV9hZ2VudCI6IG11bHRpX29rLAogICAgICAgICAg"
    "ICAidGltZW91dHMiOiB7InRhc2siOiBUQVNLX1RJTUVPVVQsICJtdWx0aSI6IE1VTFRJX1RJTUVP"
    "VVR9LAogICAgICAgICAgICAiY29uY3VycmVudCI6IGYie19hY3RpdmVfdGFza3N9L3tNQVhfQ09O"
    "Q1VSUkVOVH0iLAogICAgICAgICAgICAibWVtb3J5IjogTUVNT1JZX0ZJTEUuZXhpc3RzKCksCiAg"
    "ICAgICAgICAgICJ1c2VyX2ZpbGVzIjogVVNFUl9GSUxFU19ESVIuZXhpc3RzKCl9CgpAYXBwLmdl"
    "dCgiL2hlYWx0aC9tdWx0aSIpCmRlZiBoZWFsdGhfbXVsdGkoKToKICAgIHRyeToKICAgICAgICBm"
    "cm9tIG11bHRpX2FnZW50LmdyYXBoIGltcG9ydCBidWlsZF9ncmFwaAogICAgICAgIHJldHVybiB7"
    "Im11bHRpX2FnZW50X2VuYWJsZWQiOiBUcnVlfQogICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgog"
    "ICAgICAgIHJldHVybiB7Im11bHRpX2FnZW50X2VuYWJsZWQiOiBGYWxzZSwgImVycm9yIjogc3Ry"
    "KGUpfQoKQGFwcC5wb3N0KCIvYnJvd3NlIiwgcmVzcG9uc2VfbW9kZWw9QnJvd3NlUmVzcG9uc2Up"
    "CkBsaW1pdGVyLmxpbWl0KCIxMC9taW51dGUiKQphc3luYyBkZWYgYnJvd3NlKHJlcXVlc3Q6IFJl"
    "cXVlc3QsIGJvZHk6IEJyb3dzZVJlcXVlc3QsCiAgICAgICAgICAgICAgICAgXz1EZXBlbmRzKHZl"
    "cmlmeV9hcGlfa2V5KSk6CiAgICBpZiBub3QgbGxtOgogICAgICAgIHJhaXNlIEhUVFBFeGNlcHRp"
    "b24oNTAwLCAiTm8gTExNIGNvbmZpZ3VyZWQg4oCUIHNldCBHUk9RX0FQSV9LRVksIE9QRU5BSV9B"
    "UElfS0VZLCBBTlRIUk9QSUNfQVBJX0tFWSwgb3IgR09PR0xFX0FQSV9LRVkiKQoKICAgICMg66mU"
    "66qo66asIOy7qO2FjeyKpO2KuCDso7zsnoUKICAgIG1lbV9jdHggPSBfZ2V0X21lbW9yeV9jb250"
    "ZXh0KCkKICAgIHJhd190YXNrID0gYm9keS50YXNrCiAgICBpZiBtZW1fY3R4OgogICAgICAgIGZ1"
    "bGxfdGFzayA9IGYiW1VzZXIgY29udGV4dDoge21lbV9jdHh9XVxue2JvZHkudGFza30iCiAgICBl"
    "bHNlOgogICAgICAgIGZ1bGxfdGFzayA9IGJvZHkudGFzawogICAgZnVsbF90YXNrID0gYXBwbHlf"
    "bmF2ZXJfcHJpb3JpdHkoZnVsbF90YXNrKQogICAgaWYgYm9keS51cmw6CiAgICAgICAgZnVsbF90"
    "YXNrID0gZiJHbyB0byB7Ym9keS51cmx9IGZpcnN0LCB0aGVuIHtib2R5LnRhc2t9IgoKICAgIHN0"
    "ZXBzID0gYm9keS5tYXhfc3RlcHMgb3IgTUFYX1NURVBTCiAgICB2aXNpb24gPSBib2R5LnVzZV92"
    "aXNpb24gaWYgYm9keS51c2VfdmlzaW9uIGlzIG5vdCBOb25lIGVsc2UgVVNFX1ZJU0lPTgoKICAg"
    "IGF1ZGl0X2xvZ2dlci5pbmZvKGYiQlJPV1NFfHtyZXF1ZXN0LmNsaWVudC5ob3N0fXx7ZnVsbF90"
    "YXNrWzoxMDBdfSIpCgogICAgIyDsmpTssq3rs4Qg7ZSE66Gc67CU7J20642UIOyYpOuyhOudvOyd"
    "tOuTnAogICAgb3ZlcnJpZGVfbGxtID0gTm9uZQogICAgaWYgYm9keS5wcm92aWRlciBvciBib2R5"
    "LmFwaV9rZXk6CiAgICAgICAgdHJ5OgogICAgICAgICAgICBvdmVycmlkZV9sbG0gPSBjcmVhdGVf"
    "bGxtKAogICAgICAgICAgICAgICAgcHJvdmlkZXI9Ym9keS5wcm92aWRlciwKICAgICAgICAgICAg"
    "ICAgIGFwaV9rZXk9Ym9keS5hcGlfa2V5LAogICAgICAgICAgICAgICAgbW9kZWw9Ym9keS5tb2Rl"
    "bAogICAgICAgICAgICApCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgICAg"
    "ICByZXR1cm4gQnJvd3NlUmVzcG9uc2Uoc3VjY2Vzcz1GYWxzZSwgZXJyb3I9ZiJMTE0gb3ZlcnJp"
    "ZGUgZmFpbGVkOiB7ZX0iLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGltZXN0"
    "YW1wPWRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpKQoKICAgIGFzeW5jIHdpdGggdGFza19zbG90"
    "KCk6CiAgICAgICAgcmVzdWx0ID0gYXdhaXQgX3J1bl9hZ2VudChmdWxsX3Rhc2ssIHN0ZXBzLCB2"
    "aXNpb24sIG92ZXJyaWRlX2xsbSkKCiAgICAgICAgIyBbQU5USS1MT09QXSBTZWxmLUhlYWxpbmc6"
    "IO2DgOyehOyVhOybgy/rhKTruYTqsozsnbTshZgg7JeQ65+sIOyLnCAx7ZqM66eMIOyerOyLnOuP"
    "hAogICAgICAgIGlmIG5vdCByZXN1bHRbInN1Y2Nlc3MiXToKICAgICAgICAgICAgZXJyID0gcmVz"
    "dWx0LmdldCgiZXJyb3IiLCAiIikubG93ZXIoKQogICAgICAgICAgICByZXRyeWFibGUgPSBhbnko"
    "ayBpbiBlcnIgZm9yIGsgaW4KICAgICAgICAgICAgICAgIFsidGltZW91dCIsICJuYXZpZ2F0aW9u"
    "IiwgInRhcmdldCBjbG9zZWQiLCAic2Vzc2lvbiBjbG9zZWQiXSkKICAgICAgICAgICAgaWYgcmV0"
    "cnlhYmxlOgogICAgICAgICAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJSRVRSWXx7cmVxdWVz"
    "dC5jbGllbnQuaG9zdH0iKQogICAgICAgICAgICAgICAgcmV0cnkgPSBhd2FpdCBfcnVuX2FnZW50"
    "KGZ1bGxfdGFzaywgbWF4KHN0ZXBzLy8yLCA1KSwgdmlzaW9uLCBvdmVycmlkZV9sbG0pCiAgICAg"
    "ICAgICAgICAgICBpZiByZXRyeVsic3VjY2VzcyJdOgogICAgICAgICAgICAgICAgICAgIHJldHJ5"
    "WyJzdW1tYXJ5Il0gPSBmIltyZXRyeV0ge3JldHJ5LmdldCgnc3VtbWFyeScsJycpfSIKICAgICAg"
    "ICAgICAgICAgICAgICByZXN1bHQgPSByZXRyeQoKICAgICAgICBpZiByZXN1bHRbInN1Y2Nlc3Mi"
    "XToKICAgICAgICAgICAgX3VwZGF0ZV9tZW1vcnlfZnJvbV90YXNrKHJhd190YXNrLCByZXN1bHQu"
    "Z2V0KCJzdW1tYXJ5IiwiIikpCiAgICAgICAgICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiQlJPV1NF"
    "X09LfHN0ZXBzPXtyZXN1bHRbJ3N0ZXBzX3Rha2VuJ119fHtyZXN1bHRbJ2VsYXBzZWRfc2VjJ119"
    "cyIpCiAgICAgICAgZWxzZToKICAgICAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJCUk9XU0Vf"
    "RkFJTHx7cmVzdWx0LmdldCgnZXJyb3InLCcnKVs6MjAwXX0iKQoKICAgICAgICByZXR1cm4gQnJv"
    "d3NlUmVzcG9uc2UoCiAgICAgICAgICAgICoqcmVzdWx0LAogICAgICAgICAgICB0aW1lc3RhbXA9"
    "ZGF0ZXRpbWUubm93KCkuaXNvZm9ybWF0KCkKICAgICAgICApCgoKIyDilIDilIAg66mA7Yuw7YOt"
    "IOu4jOudvOyasOymiCDsl5Trk5ztj6zsnbjtirgg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACkBhcHAucG9zdCgiL2Jyb3dzZS9tdWx0aXRhYiIpCkBs"
    "aW1pdGVyLmxpbWl0KCI1L21pbnV0ZSIpCmFzeW5jIGRlZiBicm93c2VfbXVsdGl0YWIocmVxdWVz"
    "dDogUmVxdWVzdCwgYm9keTogTXVsdGlUYWJSZXF1ZXN0LAogICAgICAgICAgICAgICAgICAgICAg"
    "ICAgIF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkpOgogICAgIiIi7Jes65+sIOyCrOydtO2KuOul"
    "vCDsiJzssKjsoIHsnLzroZwg67Cp66y47ZWY6rOgIOqysOqzvOulvCDsooXtlakg67mE6rWQIiIi"
    "CiAgICBpZiBub3QgbGxtOgogICAgICAgIHJhaXNlIEhUVFBFeGNlcHRpb24oNTAwLCAiTm8gTExN"
    "IGNvbmZpZ3VyZWQiKQoKICAgICMgR3JvcSDrrLTro4wg66qo6424IOqyveqzoAogICAgYWN0aXZl"
    "X2xsbSA9IGxsbQogICAgaWYgYm9keS5wcm92aWRlciBvciBib2R5LmFwaV9rZXk6CiAgICAgICAg"
    "dHJ5OgogICAgICAgICAgICBhY3RpdmVfbGxtID0gY3JlYXRlX2xsbShwcm92aWRlcj1ib2R5LnBy"
    "b3ZpZGVyLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYXBpX2tleT1ib2R5"
    "LmFwaV9rZXksIG1vZGVsPWJvZHkubW9kZWwpCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBl"
    "OgogICAgICAgICAgICByZXR1cm4geyJzdWNjZXNzIjogRmFsc2UsICJlcnJvciI6IGYiTExNIG92"
    "ZXJyaWRlIGZhaWxlZDoge2V9In0KCiAgICBpZiBnZXRhdHRyKGFjdGl2ZV9sbG0sICJwcm92aWRl"
    "ciIsICIiKSA9PSAiZ3JvcSI6CiAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oIk1VTFRJVEFCX1dB"
    "Uk58Z3JvcV9wcm92aWRlcl91c2VkIikKCiAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIk1VTFRJVEFC"
    "fHtyZXF1ZXN0LmNsaWVudC5ob3N0fXx0YWJzPXtsZW4oYm9keS51cmxzKX18e2JvZHkudGFza1s6"
    "ODBdfSIpCgogICAgIyBVUkzsnbQg7JeG7Jy866m0IOyekeyXheyXkOyEnCDsnpDrj5kg7LaU7Lac"
    "IOyLnOuPhAogICAgdXJscyA9IGJvZHkudXJscwogICAgaWYgbm90IHVybHM6CiAgICAgICAgIyBM"
    "TE3sl5DqsowgVVJMIOy2lOy2nCDsmpTssq0KICAgICAgICBleHRyYWN0X3Rhc2sgPSBmIuuLpOyd"
    "jCDsnpHsl4XsnYQg7IiY7ZaJ7ZWY6riwIOychO2VtCDrsKnrrLjtlaAg7Ju57IKs7J207Yq4IFVS"
    "TOydhCDstZzrjIAgM+qwnCDstpTsspztlbTspJggKFVSTOunjCDtlZwg7KSE7JeQIO2VmOuCmOyU"
    "qSk6IHtib2R5LnRhc2t9IgogICAgICAgIHRyeToKICAgICAgICAgICAgZnJvbSBsYW5nY2hhaW5f"
    "Y29yZS5tZXNzYWdlcyBpbXBvcnQgSHVtYW5NZXNzYWdlCiAgICAgICAgICAgIHJlc3AgPSBhd2Fp"
    "dCBhY3RpdmVfbGxtLmFpbnZva2UoW0h1bWFuTWVzc2FnZShjb250ZW50PWV4dHJhY3RfdGFzayld"
    "KQogICAgICAgICAgICBpbXBvcnQgcmUgYXMgX3JlMwogICAgICAgICAgICBmb3VuZF91cmxzID0g"
    "X3JlMy5maW5kYWxsKHInaHR0cHM/Oi8vW15cczw+Il0rJywgcmVzcC5jb250ZW50KQogICAgICAg"
    "ICAgICB1cmxzID0gZm91bmRfdXJsc1s6NV0KICAgICAgICBleGNlcHQgRXhjZXB0aW9uOgogICAg"
    "ICAgICAgICB1cmxzID0gW10KCiAgICBpZiBub3QgdXJsczoKICAgICAgICAjIOuEpOydtOuyhCDq"
    "soDsg4nsnLzroZwg7Y+067CxCiAgICAgICAgdXJscyA9IFtmImh0dHBzOi8vc2VhcmNoLm5hdmVy"
    "LmNvbS9zZWFyY2gubmF2ZXI/cXVlcnk9e2JvZHkudGFza30iXQoKICAgICMg6rCBIO2DrShVUkwp"
    "67OE66GcIOyInOywqCDsi6TtlokKICAgIHRhYl9yZXN1bHRzID0gW10KICAgIGFzeW5jIHdpdGgg"
    "dGFza19zbG90KCk6CiAgICAgICAgZm9yIGksIHVybCBpbiBlbnVtZXJhdGUodXJsc1s6NV0pOgog"
    "ICAgICAgICAgICB0YWJfdGFzayA9IGYiR28gdG8ge3VybH0gYW5kIGZpbmQgaW5mb3JtYXRpb24g"
    "YWJvdXQ6IHtib2R5LnRhc2t9LiBFeHRyYWN0IGtleSBkYXRhIGNvbmNpc2VseS4iCiAgICAgICAg"
    "ICAgIHRyeToKICAgICAgICAgICAgICAgIHNlc3Npb24gPSBCcm93c2VyU2Vzc2lvbihicm93c2Vy"
    "X3Byb2ZpbGU9QnJvd3NlclByb2ZpbGUoCiAgICAgICAgICAgICAgICAgICAgaGVhZGxlc3M9VHJ1"
    "ZSwgZGlzYWJsZV9zZWN1cml0eT1GYWxzZSwKICAgICAgICAgICAgICAgICAgICB2aWV3cG9ydD17"
    "IndpZHRoIjogMTI4MCwgImhlaWdodCI6IDcyMH0pKQogICAgICAgICAgICAgICAgYWdlbnQgPSBB"
    "Z2VudCh0YXNrPXRhYl90YXNrLCBsbG09YWN0aXZlX2xsbSwKICAgICAgICAgICAgICAgICAgICAg"
    "ICAgICAgICAgYnJvd3Nlcl9zZXNzaW9uPXNlc3Npb24sCiAgICAgICAgICAgICAgICAgICAgICAg"
    "ICAgICAgIHVzZV92aXNpb249RmFsc2UsIG1heF9hY3Rpb25zX3Blcl9zdGVwPTMpCiAgICAgICAg"
    "ICAgICAgICByZXN1bHQgPSBhd2FpdCBhc3luY2lvLndhaXRfZm9yKAogICAgICAgICAgICAgICAg"
    "ICAgIGFnZW50LnJ1bihtYXhfc3RlcHM9Ym9keS5tYXhfc3RlcHNfcGVyX3RhYiksCiAgICAgICAg"
    "ICAgICAgICAgICAgdGltZW91dD1UQVNLX1RJTUVPVVQKICAgICAgICAgICAgICAgICkKICAgICAg"
    "ICAgICAgICAgIGZpbmFsID0gcmVzdWx0LmZpbmFsX3Jlc3VsdCgpIGlmIHJlc3VsdCBlbHNlICJb"
    "6rKw6rO87JeG7J2MXSIKICAgICAgICAgICAgICAgIHRhYl9yZXN1bHRzLmFwcGVuZCh7InRhYiI6"
    "IGkrMSwgInVybCI6IHVybCwgInJlc3VsdCI6IGZpbmFsWzozMDAwXSwgInN1Y2Nlc3MiOiBUcnVl"
    "fSkKICAgICAgICAgICAgZXhjZXB0IGFzeW5jaW8uVGltZW91dEVycm9yOgogICAgICAgICAgICAg"
    "ICAgdGFiX3Jlc3VsdHMuYXBwZW5kKHsidGFiIjogaSsxLCAidXJsIjogdXJsLCAicmVzdWx0Ijog"
    "Ilvtg4DsnoTslYTsm4NdIiwgInN1Y2Nlc3MiOiBGYWxzZX0pCiAgICAgICAgICAgIGV4Y2VwdCBF"
    "eGNlcHRpb24gYXMgZToKICAgICAgICAgICAgICAgIHRhYl9yZXN1bHRzLmFwcGVuZCh7InRhYiI6"
    "IGkrMSwgInVybCI6IHVybCwgInJlc3VsdCI6IGYiW+yYpOulmDoge3N0cihlKVs6MjAwXX1dIiwg"
    "InN1Y2Nlc3MiOiBGYWxzZX0pCiAgICAgICAgICAgIGZpbmFsbHk6CiAgICAgICAgICAgICAgICB0"
    "cnk6CiAgICAgICAgICAgICAgICAgICAgaWYgJ3Nlc3Npb24nIGluIGxvY2FscygpOiBhd2FpdCBh"
    "c3luY2lvLndhaXRfZm9yKHNlc3Npb24uY2xvc2UoKSwgdGltZW91dD01KQogICAgICAgICAgICAg"
    "ICAgZXhjZXB0OiBwYXNzCgogICAgICAgICMg6rKw6rO8IOyihe2VqSDruYTqtZAKICAgICAgICBj"
    "b21wYXJlX3Byb21wdCA9IGYi64uk7J2M7J2AIOyXrOufrCDsgqzsnbTtirjsl5DshJwg7IiY7KeR"
    "7ZWcIOqysOqzvOyeheuLiOuLpC4gJ3tib2R5LnRhc2t9J+yXkCDrjIDtlbQg7KKF7ZWpIOu5hOq1"
    "kCDrtoTshJ3tlbTso7zshLjsmpQ6XG5cbiIKICAgICAgICBmb3IgdHIgaW4gdGFiX3Jlc3VsdHM6"
    "CiAgICAgICAgICAgIGNvbXBhcmVfcHJvbXB0ICs9IGYiW+2DrXt0clsndGFiJ119IC0ge3RyWyd1"
    "cmwnXX1dXG57dHJbJ3Jlc3VsdCddfVxuXG4iCiAgICAgICAgY29tcGFyZV9wcm9tcHQgKz0gIuyc"
    "hCDqsrDqs7zrpbwg67mE6rWQIOu2hOyEne2VmOqzoCwg7ZW17Ius7J2EIO2VnOq1reyWtOuhnCDs"
    "oJXrpqztlbTso7zshLjsmpQuIgoKICAgICAgICB0cnk6CiAgICAgICAgICAgIGZyb20gbGFuZ2No"
    "YWluX2NvcmUubWVzc2FnZXMgaW1wb3J0IEh1bWFuTWVzc2FnZQogICAgICAgICAgICBzdW1tYXJ5"
    "ID0gYXdhaXQgYXN5bmNpby53YWl0X2ZvcigKICAgICAgICAgICAgICAgIGFjdGl2ZV9sbG0uYWlu"
    "dm9rZShbSHVtYW5NZXNzYWdlKGNvbnRlbnQ9Y29tcGFyZV9wcm9tcHQpXSksCiAgICAgICAgICAg"
    "ICAgICB0aW1lb3V0PTYwCiAgICAgICAgICAgICkKICAgICAgICAgICAgZmluYWxfc3VtbWFyeSA9"
    "IHN1bW1hcnkuY29udGVudAogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAg"
    "ICAgZmluYWxfc3VtbWFyeSA9ICJcbi0tLVxuIi5qb2luKFtmIlvtg617clsndGFiJ119XSB7clsn"
    "cmVzdWx0J11bOjUwMF19IiBmb3IgciBpbiB0YWJfcmVzdWx0c10pCgogICAgIyDrqZTrqqjrpqwg"
    "7JeF642w7J207Yq4CiAgICBfdXBkYXRlX21lbW9yeV9mcm9tX3Rhc2soYm9keS50YXNrLCBmaW5h"
    "bF9zdW1tYXJ5Wzo1MDBdKQogICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJNVUxUSVRBQl9PS3x0YWJz"
    "PXtsZW4odGFiX3Jlc3VsdHMpfSIpCgogICAgcmV0dXJuIHsKICAgICAgICAic3VjY2VzcyI6IFRy"
    "dWUsCiAgICAgICAgInN1bW1hcnkiOiBmaW5hbF9zdW1tYXJ5LAogICAgICAgICJ0YWJzIjogdGFi"
    "X3Jlc3VsdHMsCiAgICAgICAgInRhYl9jb3VudCI6IGxlbih0YWJfcmVzdWx0cyksCiAgICAgICAg"
    "InRpbWVzdGFtcCI6IGRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpCiAgICB9CgojIE11bHRpLUFn"
    "ZW50IOyXlOuTnO2PrOyduO2KuApAYXBwLnBvc3QoIi9icm93c2UvbXVsdGkiKQpAbGltaXRlci5s"
    "aW1pdCgiNS9taW51dGUiKQphc3luYyBkZWYgYnJvd3NlX211bHRpKHJlcXVlc3Q6IFJlcXVlc3Qs"
    "IGJvZHk6IEJyb3dzZVJlcXVlc3QsCiAgICAgICAgICAgICAgICAgICAgICAgXz1EZXBlbmRzKHZl"
    "cmlmeV9hcGlfa2V5KSk6CiAgICB0cnk6CiAgICAgICAgZnJvbSBtdWx0aV9hZ2VudC5ncmFwaCBp"
    "bXBvcnQgYnVpbGRfZ3JhcGgKICAgIGV4Y2VwdCBJbXBvcnRFcnJvcjoKICAgICAgICByYWlzZSBI"
    "VFRQRXhjZXB0aW9uKDUwMSwgIk11bHRpLUFnZW50IG5vdCBhdmFpbGFibGUgKEdST1FfQVBJX0tF"
    "WSByZXF1aXJlZCkiKQoKICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiTVVMVEl8e3JlcXVlc3QuY2xp"
    "ZW50Lmhvc3R9fHtib2R5LnRhc2tbOjEwMF19IikKCiAgICBhc3luYyB3aXRoIHRhc2tfc2xvdCgp"
    "OgogICAgICAgIHRyeToKICAgICAgICAgICAgZ3JhcGggPSBidWlsZF9ncmFwaCgpCiAgICAgICAg"
    "ICAgIHN0YXRlID0geyJvcmlnaW5hbF90YXNrIjogYm9keS50YXNrLCAibWVzc2FnZXMiOiBbXSwK"
    "ICAgICAgICAgICAgICAgICAgICAgInJlc2VhcmNoX3Jlc3VsdHMiOiBbXSwgImJyb3dzZXJfcmVz"
    "dWx0cyI6IFtdLAogICAgICAgICAgICAgICAgICAgICAiaXRlcmF0aW9uIjogMCwgInJvdXRlX2hp"
    "c3RvcnkiOiBbXSwgIm5leHQiOiAic3VwZXJ2aXNvciJ9CgogICAgICAgICAgICAjIFtBTlRJLUxP"
    "T1BdIE11bHRpLUFnZW50IOyghOyytCDtg4DsnoTslYTsm4MKICAgICAgICAgICAgZmluYWwgPSBh"
    "d2FpdCBhc3luY2lvLndhaXRfZm9yKAogICAgICAgICAgICAgICAgZ3JhcGguYWludm9rZShzdGF0"
    "ZSksCiAgICAgICAgICAgICAgICB0aW1lb3V0PU1VTFRJX1RJTUVPVVQKICAgICAgICAgICAgKQoK"
    "ICAgICAgICAgICAgbXNncyA9IGZpbmFsLmdldCgibWVzc2FnZXMiLCBbXSkKICAgICAgICAgICAg"
    "bGFzdCA9IG1zZ3NbLTFdLmNvbnRlbnQgaWYgbXNncyBlbHNlICJubyByZXN1bHQiCiAgICAgICAg"
    "ICAgIHRva2VuX2luZm8gPSB7fQogICAgICAgICAgICBpZiAidG9rZW5fdHJhY2tlciIgaW4gZmlu"
    "YWwgYW5kIGZpbmFsWyJ0b2tlbl90cmFja2VyIl06CiAgICAgICAgICAgICAgICB0b2tlbl9pbmZv"
    "ID0gZmluYWxbInRva2VuX3RyYWNrZXIiXS5zdW1tYXJ5CgogICAgICAgICAgICBhdWRpdF9sb2dn"
    "ZXIuaW5mbyhmIk1VTFRJX09LfHRva2Vucz17dG9rZW5faW5mby5nZXQoJ3RvdGFsX3Rva2Vucycs"
    "MCl9IikKICAgICAgICAgICAgcmV0dXJuIHsic3VjY2VzcyI6IFRydWUsICJyZXN1bHQiOiBsYXN0"
    "LAogICAgICAgICAgICAgICAgICAgICJ0b2tlbl91c2FnZSI6IHRva2VuX2luZm8sCiAgICAgICAg"
    "ICAgICAgICAgICAgInRpbWVzdGFtcCI6IGRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpfQoKICAg"
    "ICAgICBleGNlcHQgYXN5bmNpby5UaW1lb3V0RXJyb3I6CiAgICAgICAgICAgIGF1ZGl0X2xvZ2dl"
    "ci5pbmZvKGYiTVVMVElfVElNRU9VVHx7TVVMVElfVElNRU9VVH1zIikKICAgICAgICAgICAgcmV0"
    "dXJuIHsic3VjY2VzcyI6IEZhbHNlLAogICAgICAgICAgICAgICAgICAgICJlcnJvciI6IGYiTXVs"
    "dGktQWdlbnQgdGltZWQgb3V0IGFmdGVyIHtNVUxUSV9USU1FT1VUfXMiLAogICAgICAgICAgICAg"
    "ICAgICAgICJ0aW1lc3RhbXAiOiBkYXRldGltZS5ub3coKS5pc29mb3JtYXQoKX0KICAgICAgICBl"
    "eGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAgICAgICAgICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiTVVM"
    "VElfRkFJTHx7ZX0iKQogICAgICAgICAgICByZXR1cm4geyJzdWNjZXNzIjogRmFsc2UsICJlcnJv"
    "ciI6IHN0cihlKSwKICAgICAgICAgICAgICAgICAgICAidGltZXN0YW1wIjogZGF0ZXRpbWUubm93"
    "KCkuaXNvZm9ybWF0KCl9CgoKCiMg4pSA4pSAIOuplOuqqOumrCDsl5Trk5ztj6zsnbjtirgg4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSACkBhcHAuZ2V0KCIvbWVtb3J5IikKYXN5bmMgZGVmIGdldF9tZW1vcnko"
    "Xz1EZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAgICByZXR1cm4gX2xvYWRfbWVtb3J5KCkKCkBh"
    "cHAucG9zdCgiL21lbW9yeSIpCmFzeW5jIGRlZiB1cGRhdGVfbWVtb3J5KHJlcXVlc3Q6IFJlcXVl"
    "c3QsIF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkpOgogICAgYm9keSA9IGF3YWl0IHJlcXVlc3Qu"
    "anNvbigpCiAgICBtZW0gPSBfbG9hZF9tZW1vcnkoKQogICAgaWYgImxvY2F0aW9uIiBpbiBib2R5"
    "OiBtZW1bImxvY2F0aW9uIl0gPSBzdHIoYm9keVsibG9jYXRpb24iXSlbOjUwXQogICAgaWYgImlu"
    "dGVyZXN0cyIgaW4gYm9keTogbWVtWyJpbnRlcmVzdHMiXSA9IFtzdHIoaSlbOjMwXSBmb3IgaSBp"
    "biBib2R5WyJpbnRlcmVzdHMiXVs6MjBdXQogICAgaWYgInByZWZlcmVuY2VzIiBpbiBib2R5OiBt"
    "ZW1bInByZWZlcmVuY2VzIl0udXBkYXRlKGJvZHlbInByZWZlcmVuY2VzIl0pCiAgICBpZiAiZmFj"
    "dHMiIGluIGJvZHk6IG1lbVsiZmFjdHMiXSA9IChtZW0uZ2V0KCJmYWN0cyIsW10pICsgW3N0cihm"
    "KVs6MjAwXSBmb3IgZiBpbiBib2R5WyJmYWN0cyJdXSlbLTMwOl0KICAgIF9zYXZlX21lbW9yeSht"
    "ZW0pCiAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIk1FTU9SWV9VUERBVEV8e2xpc3QoYm9keS5rZXlz"
    "KCkpfSIpCiAgICByZXR1cm4geyJzdWNjZXNzIjogVHJ1ZSwgIm1lbW9yeSI6IG1lbX0KCkBhcHAu"
    "ZGVsZXRlKCIvbWVtb3J5IikKYXN5bmMgZGVmIGNsZWFyX21lbW9yeShfPURlcGVuZHModmVyaWZ5"
    "X2FwaV9rZXkpKToKICAgIF9zYXZlX21lbW9yeSh7ImxvY2F0aW9uIjoiIiwiaW50ZXJlc3RzIjpb"
    "XSwicHJlZmVyZW5jZXMiOnt9LCJmYWN0cyI6W10sInBhc3RfcXVlcmllcyI6W119KQogICAgcmV0"
    "dXJuIHsic3VjY2VzcyI6IFRydWUsICJtZXNzYWdlIjogIk1lbW9yeSBjbGVhcmVkIn0KCiMg4pSA"
    "4pSAIO2MjOydvCDsoJHqt7wg7JeU65Oc7Y+s7J247Yq4IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApAYXBwLmdldCgiL2Zp"
    "bGVzIikKYXN5bmMgZGVmIGxpc3RfZmlsZXMoXz1EZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAg"
    "ICBpZiBub3QgVVNFUl9GSUxFU19ESVIuZXhpc3RzKCk6CiAgICAgICAgcmV0dXJuIHsiZmlsZXMi"
    "OiBbXSwgIm1lc3NhZ2UiOiAiTm8gdXNlcl9maWxlcyBkaXJlY3RvcnkifQogICAgZmlsZXMgPSBb"
    "XQogICAgZm9yIGYgaW4gc29ydGVkKFVTRVJfRklMRVNfRElSLml0ZXJkaXIoKSk6CiAgICAgICAg"
    "aWYgZi5pc19maWxlKCkgYW5kIGYuc3VmZml4Lmxvd2VyKCkgaW4gQUxMT1dFRF9GSUxFX0VYVDoK"
    "ICAgICAgICAgICAgZmlsZXMuYXBwZW5kKHsibmFtZSI6IGYubmFtZSwgInNpemUiOiBmLnN0YXQo"
    "KS5zdF9zaXplLAogICAgICAgICAgICAgICAgICAgICAgICAgICJtb2RpZmllZCI6IGRhdGV0aW1l"
    "LmZyb210aW1lc3RhbXAoZi5zdGF0KCkuc3RfbXRpbWUpLmlzb2Zvcm1hdCgpfSkKICAgIHJldHVy"
    "biB7ImZpbGVzIjogZmlsZXMsICJjb3VudCI6IGxlbihmaWxlcyl9CgpAYXBwLmdldCgiL2ZpbGVz"
    "L3tmaWxlbmFtZX0iKQphc3luYyBkZWYgcmVhZF9maWxlKGZpbGVuYW1lOiBzdHIsIF89RGVwZW5k"
    "cyh2ZXJpZnlfYXBpX2tleSkpOgogICAgdHJ5OgogICAgICAgIHBhdGggPSBfc2FmZV9wYXRoKGZp"
    "bGVuYW1lKQogICAgICAgIGlmIG5vdCBwYXRoLmV4aXN0cygpOgogICAgICAgICAgICByYWlzZSBI"
    "VFRQRXhjZXB0aW9uKDQwNCwgZiJGaWxlIG5vdCBmb3VuZDoge2ZpbGVuYW1lfSIpCiAgICAgICAg"
    "aWYgcGF0aC5zdWZmaXgubG93ZXIoKSBpbiAoIi5wZGYiLCAiLnhsc3giLCAiLnhscyIsICIuZG9j"
    "eCIpOgogICAgICAgICAgICByZXR1cm4geyJuYW1lIjogZmlsZW5hbWUsICJ0eXBlIjogcGF0aC5z"
    "dWZmaXgsCiAgICAgICAgICAgICAgICAgICAgIm1lc3NhZ2UiOiAiQmluYXJ5IGZpbGUg4oCUIHVz"
    "ZSAvYnJvd3NlIHRvIGFzayBBSSB0byBhbmFseXplIGl0In0KICAgICAgICB0ZXh0ID0gcGF0aC5y"
    "ZWFkX3RleHQoInV0Zi04IiwgZXJyb3JzPSJyZXBsYWNlIilbOjUwMDAwXQogICAgICAgIHJldHVy"
    "biB7Im5hbWUiOiBmaWxlbmFtZSwgImNvbnRlbnQiOiB0ZXh0LCAic2l6ZSI6IGxlbih0ZXh0KX0K"
    "ICAgIGV4Y2VwdCBWYWx1ZUVycm9yIGFzIGU6CiAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbig0"
    "MDAsIHN0cihlKSkKCkBhcHAucG9zdCgiL2ZpbGVzL3tmaWxlbmFtZX0iKQpAbGltaXRlci5saW1p"
    "dCgiMTAvbWludXRlIikKYXN5bmMgZGVmIHdyaXRlX2ZpbGUocmVxdWVzdDogUmVxdWVzdCwgZmls"
    "ZW5hbWU6IHN0ciwgXz1EZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAgICB0cnk6CiAgICAgICAg"
    "cGF0aCA9IF9zYWZlX3BhdGgoZmlsZW5hbWUpCiAgICAgICAgYm9keSA9IGF3YWl0IHJlcXVlc3Qu"
    "anNvbigpCiAgICAgICAgdGV4dCA9IHN0cihib2R5LmdldCgiY29udGVudCIsICIiKSlbOjEwMDAw"
    "MF0KICAgICAgICBVU0VSX0ZJTEVTX0RJUi5ta2RpcihwYXJlbnRzPVRydWUsIGV4aXN0X29rPVRy"
    "dWUpCiAgICAgICAgcGF0aC53cml0ZV90ZXh0KHRleHQsICJ1dGYtOCIpCiAgICAgICAgYXVkaXRf"
    "bG9nZ2VyLmluZm8oZiJGSUxFX1dSSVRFfHtmaWxlbmFtZX18e2xlbih0ZXh0KX1ieXRlcyIpCiAg"
    "ICAgICAgcmV0dXJuIHsic3VjY2VzcyI6IFRydWUsICJuYW1lIjogZmlsZW5hbWUsICJzaXplIjog"
    "bGVuKHRleHQpfQogICAgZXhjZXB0IFZhbHVlRXJyb3IgYXMgZToKICAgICAgICByYWlzZSBIVFRQ"
    "RXhjZXB0aW9uKDQwMCwgc3RyKGUpKQoKIyBbU0VDVVJJVFldIOyDge2DnCDtmZXsnbjsmqkgKOq0"
    "gOumrOyekCDsoITsmqkpCkBhcHAuZ2V0KCIvbWV0cmljcyIpCmFzeW5jIGRlZiBtZXRyaWNzKHJl"
    "cXVlc3Q6IFJlcXVlc3QsIF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkpOgogICAgcmV0dXJuIHsK"
    "ICAgICAgICAiYWN0aXZlX3Rhc2tzIjogX2FjdGl2ZV90YXNrcywKICAgICAgICAibWF4X2NvbmN1"
    "cnJlbnQiOiBNQVhfQ09OQ1VSUkVOVCwKICAgICAgICAibW9kZWwiOiBHUk9RX01PREVMLAogICAg"
    "ICAgICJ0aW1lb3V0cyI6IHsKICAgICAgICAgICAgInRhc2siOiBUQVNLX1RJTUVPVVQsCiAgICAg"
    "ICAgICAgICJtdWx0aSI6IE1VTFRJX1RJTUVPVVQsCiAgICAgICAgICAgICJzdGVwIjogU1RFUF9U"
    "SU1FT1VUCiAgICAgICAgfQogICAgfQoKaWYgX19uYW1lX18gPT0gIl9fbWFpbl9fIjoKICAgIGlt"
    "cG9ydCB1dmljb3JuCiAgICB1dmljb3JuLnJ1bihhcHAsIGhvc3Q9IjAuMC4wLjAiLCBwb3J0PTgw"
    "MDEsCiAgICAgICAgICAgICAgICBzZXJ2ZXJfaGVhZGVyPUZhbHNlLCAgIyBbU0VDVVJJVFldIOyE"
    "nOuyhCDtl6TrjZQg7Iio6rmACiAgICAgICAgICAgICAgICBhY2Nlc3NfbG9nPVRydWUpCg=="
)
dest = os.environ.get('AGENT_DIR','') + '/agent_server.py'
with open(dest, 'w', encoding='utf-8') as f:
    f.write(base64.b64decode(b64).decode('utf-8'))
print('  ✅ agent_server.py v6.4.0 생성 완료')
WRITE_AGENT
ok "FILE 4/6  agent_server.py"

# ── FILE 4.5: Multi-Agent 모듈 (7개 파일) ───────────────────────────
mkdir -p "${AGENT_DIR}/multi_agent"

cat > "${AGENT_DIR}/multi_agent/__init__.py" << 'MAEOF'
"""Multi-Agent System v5.0"""
MAEOF

cat > "${AGENT_DIR}/multi_agent/state.py" << 'MAEOF'
from __future__ import annotations
import operator
from typing import Annotated, Any, Literal, TypedDict
from langchain_core.messages import BaseMessage

class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], operator.add]
    next: Literal["research", "browser", "summarizer", "END"]
    original_task: str
    research_results: list[str]
    browser_results: list[str]
    iteration: int
    route_history: list[str]
    model: str
    token_tracker: Any
MAEOF

cat > "${AGENT_DIR}/multi_agent/groq_utils.py" << 'MAEOF'
from __future__ import annotations
import asyncio, logging, time
from dataclasses import dataclass, field
from typing import Any
from langchain_core.messages import BaseMessage
from langchain_groq import ChatGroq

logger = logging.getLogger("multi_agent.groq_utils")

MODEL_LIMITS = {
    "llama-3.3-70b-versatile":{"context":131072,"max_output":32768,"in_cost":0.59,"out_cost":0.79},
    "llama-3.1-8b-instant":{"context":131072,"max_output":8192,"in_cost":0.05,"out_cost":0.08},
    "_default":{"context":32768,"max_output":8192,"in_cost":1.0,"out_cost":1.0},
}
ROLE_MAX_TOKENS = {"supervisor":256,"research":2048,"browser":1536,"summarizer":4096}

def _lim(m): return MODEL_LIMITS.get(m, MODEL_LIMITS["_default"])

def est_tok(text):
    if not text: return 0
    kr = sum(1 for c in text if '가' <= c <= '힣')
    return max(1, int(len(text) / (2.0 if kr > len(text)*0.3 else 3.0)))

def est_msgs_tok(msgs):
    return sum(4+est_tok(m.content if isinstance(m.content,str) else str(m.content)) for m in msgs)

def trunc(text, mt):
    if est_tok(text) <= mt: return text
    return text[:int(len(text)*(mt/est_tok(text))*0.9)] + "
[...절삭]"

def trunc_list(results, mt, keep=3):
    if not results: return results
    t = results[-keep:]
    per = mt // len(t)
    return [trunc(r, per) for r in t]

def prep_ctx(sp, uc, model, role):
    l = _lim(model); mo = min(ROLE_MAX_TOKENS.get(role,2048), l["max_output"])
    bud = l["context"] - mo - 500; st = est_tok(sp)
    if st + est_tok(uc) > bud: uc = trunc(uc, max(200, bud-st))
    return uc, mo

@dataclass
class GroqModelConfig:
    light: str = "llama-3.1-8b-instant"
    heavy: str = "llama-3.3-70b-versatile"
    lt: float = 0.0; ht: float = 0.3
    def get_llm(self, role):
        m,t = (self.light,self.lt) if role=="supervisor" else (self.heavy,self.ht)
        return ChatGroq(model=m, temperature=t, max_tokens=min(ROLE_MAX_TOKENS.get(role,2048), _lim(m)["max_output"]))
    def name(self, role):
        return self.light if role=="supervisor" else self.heavy

model_config = GroqModelConfig()

@dataclass
class TokenTracker:
    ti:int=0; to:int=0; cost:float=0.0; calls:int=0
    _by:dict=field(default_factory=dict); budget:float=0.0
    def record(self, nd, inp, out, mdl=""):
        self.ti+=inp; self.to+=out; self.calls+=1
        l=_lim(mdl); c=(inp/1e6)*l["in_cost"]+(out/1e6)*l["out_cost"]; self.cost+=c
        if nd not in self._by: self._by[nd]={"in":0,"out":0,"calls":0,"cost":0.0}
        n=self._by[nd]; n["in"]+=inp; n["out"]+=out; n["calls"]+=1; n["cost"]+=c
    def over(self): return self.budget>0 and self.cost>=self.budget
    @property
    def summary(self):
        return {"total_tokens":self.ti+self.to,"cost_usd":round(self.cost,6),"api_calls":self.calls,"by_node":self._by}

_lr=0.0; _lk=asyncio.Lock(); MI=0.5
RP=["rate_limit","rate limit","429","too many"]; TP=["503","502","timeout","500"]

async def invoke_retry(llm, msgs, retries=4, base=1.0, node="?", tracker=None):
    global _lr
    if tracker and tracker.over(): raise RuntimeError(f"예산초과(${tracker.cost:.4f})")
    ie = est_msgs_tok(msgs)
    for a in range(retries+1):
        try:
            async with _lk:
                now=time.time()
                if now-_lr<MI: await asyncio.sleep(MI-(now-_lr))
                _lr=time.time()
            r = await llm.ainvoke(msgs)
            if tracker:
                ot=est_tok(r.content if isinstance(r.content,str) else str(r.content))
                tracker.record(node, ie, ot, getattr(llm,"model_name","") or getattr(llm,"model",""))
            return r
        except Exception as e:
            msg=str(e).lower()
            if a>=retries: raise
            if any(p in msg for p in RP): d=min(base*(3**a),30)
            elif any(p in msg for p in TP): d=min(base*(2**a),30)
            else: raise
            logger.warning(f"[{node}] retry {a+1}/{retries+1} — {d:.0f}s")
            await asyncio.sleep(d)
MAEOF

cat > "${AGENT_DIR}/multi_agent/supervisor.py" << 'MAEOF'
from __future__ import annotations
import json, logging
from typing import Any
from langchain_core.messages import HumanMessage, SystemMessage
from .state import AgentState
from .groq_utils import invoke_retry, model_config

logger = logging.getLogger("multi_agent.supervisor")
MX_IT=6; MX_CON=3
PROMPT=('Supervisor. JSON만 출력: {"next":"research|browser|summarizer","reason":"이유"}
'
        'research=조사, browser=웹접속, summarizer=종합')

async def supervisor_node(state: AgentState) -> dict[str, Any]:
    it=state.get("iteration",0)+1; hist=list(state.get("route_history",[]))
    res=state.get("research_results",[]); bro=state.get("browser_results",[])
    task=state.get("original_task","")
    if it>MX_IT:
        hist.append("summarizer"); return {"next":"summarizer","iteration":it,"route_history":hist}
    if len(hist)>=MX_CON and len(set(hist[-MX_CON:]))==1 and hist[-1]!="summarizer":
        hist.append("summarizer"); return {"next":"summarizer","iteration":it,"route_history":hist}
    ctx=[f"[요청]{task}"]
    if res: ctx.append(f"[Research {len(res)}건]")
    if bro: ctx.append(f"[Browser {len(bro)}건]")
    ctx.append(f"[반복]{it}/{MX_IT}")
    llm=model_config.get_llm("supervisor")
    msgs=[SystemMessage(content=PROMPT),HumanMessage(content="
".join(ctx))]
    try:
        r=await invoke_retry(llm,msgs,retries=3,node="supervisor",tracker=state.get("token_tracker"))
        dec=_parse(r.content)
        if dec not in ("research","browser","summarizer"): dec="summarizer"
        hist.append(dec); return {"next":dec,"iteration":it,"route_history":hist}
    except Exception:
        fb="summarizer" if (res or bro) else "research"
        hist.append(fb); return {"next":fb,"iteration":it,"route_history":hist}

def _parse(raw):
    t=raw.strip()
    if "```" in t:
        for b in t.split("```"):
            b=b.strip().removeprefix("json").strip()
            if b.startswith("{"): t=b; break
    try: return json.loads(t).get("next","research")
    except (json.JSONDecodeError,AttributeError,TypeError):
        l=t.lower()
        if "summarizer" in l: return "summarizer"
        if "browser" in l: return "browser"
        return "research"
MAEOF

cat > "${AGENT_DIR}/multi_agent/research_agent.py" << 'MAEOF'
from __future__ import annotations
import logging
from typing import Any
from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from .state import AgentState
from .groq_utils import invoke_retry, model_config, trunc_list, prep_ctx

logger = logging.getLogger("multi_agent.research")
PROMPT=("리서치 에이전트. 체계적으로 조사.
"
        "불확실→[확인 필요], 브라우저 필요→[브라우저 필요: URL]. 한국어.")

async def research_node(state: AgentState) -> dict[str, Any]:
    task=state.get("original_task",""); ex=state.get("research_results",[])
    bro=state.get("browser_results",[]); tr=state.get("token_tracker")
    sr=trunc_list(ex,3000); sb=trunc_list(bro,2000)
    p=[f"요청: {task}"]
    if sr: p.append("[이전조사]
"+"
---
".join(sr))
    if sb: p.append("[브라우저데이터]
"+"
---
".join(sb))
    if ex: p.append("중복없이 보완만.")
    user="
".join(p)
    mn=model_config.name("research"); user,_=prep_ctx(PROMPT,user,mn,"research")
    llm=model_config.get_llm("research")
    msgs=[SystemMessage(content=PROMPT),HumanMessage(content=user)]
    try:
        r=await invoke_retry(llm,msgs,retries=4,node="research",tracker=tr)
        txt=r.content.strip()
        return {"messages":[AIMessage(content=f"[Research]{txt}",name="research")],"research_results":[txt]}
    except Exception as e:
        err=f"[Research오류]{e}"
        return {"messages":[AIMessage(content=err,name="research")],"research_results":[err]}
MAEOF

cat > "${AGENT_DIR}/multi_agent/browser_tool_agent.py" << 'MAEOF'
"""Browser Agent v6 — Browser Use 기반 (Xvfb/VNC 의존 제거)"""
from __future__ import annotations
import asyncio, logging, os, re
from typing import Any
from langchain_core.messages import AIMessage
from pydantic import Field as PydanticField
from browser_use import Agent, BrowserSession
from browser_use.browser import BrowserProfile
from .state import AgentState

def _make_provider_class(base_cls, name):
    return type(f"{name}LLM", (base_cls,), {
        "__annotations__": {"provider": str},
        "provider": PydanticField(default=name),
        "model_config": {"extra": "allow"},
    })

logger = logging.getLogger("multi_agent.browser")

def _get_llm():
    provider = os.environ.get("LLM_PROVIDER", "").lower()
    if os.environ.get("OPENAI_API_KEY") or provider == "openai":
        from langchain_openai import ChatOpenAI
        C = _make_provider_class(ChatOpenAI, "openai")
        return C(model=os.environ.get("OPENAI_MODEL","gpt-4o"),
                 api_key=os.environ.get("OPENAI_API_KEY",""), temperature=0)
    elif os.environ.get("ANTHROPIC_API_KEY") or provider in ("anthropic","claude"):
        from langchain_anthropic import ChatAnthropic
        C = _make_provider_class(ChatAnthropic, "anthropic")
        return C(model=os.environ.get("ANTHROPIC_MODEL","claude-sonnet-4-20250514"),
                 api_key=os.environ.get("ANTHROPIC_API_KEY",""), temperature=0)
    elif os.environ.get("GOOGLE_API_KEY") or provider in ("google","gemini"):
        from langchain_google_genai import ChatGoogleGenerativeAI
        C = _make_provider_class(ChatGoogleGenerativeAI, "google")
        return C(model=os.environ.get("GOOGLE_MODEL","gemini-2.5-flash"),
                 google_api_key=os.environ.get("GOOGLE_API_KEY",""), temperature=0)
    else:
        key = os.environ.get("GROQ_API_KEY", "")
        if not key: return None
        from langchain_groq import ChatGroq
        C = _make_provider_class(ChatGroq, "groq")
        return C(model_name=os.environ.get("GROQ_MODEL","llama-3.3-70b-versatile"),
                 api_key=key, temperature=0, max_retries=3)

async def _run_browser_task(task, max_steps=7):
    llm = _get_llm()
    if not llm: return "[오류] GROQ_API_KEY 미설정"
    session = None
    try:
        session = BrowserSession(browser_profile=BrowserProfile(
            headless=True, viewport={"width": 1280, "height": 720}))
        agent = Agent(task=task, llm=llm, browser_session=session,
                      use_vision=False, max_actions_per_step=3)
        # [ANTI-LOOP] 타임아웃 적용
        result = await asyncio.wait_for(
            agent.run(max_steps=max_steps), timeout=120)
        return result.final_result() if result else "[결과없음]"
    except asyncio.TimeoutError:
        return "[타임아웃] 120초 초과"
    except Exception as e:
        return f"[오류]{e}"
    finally:
        if session:
            try: await session.close()
            except: pass

async def browser_node(state):
    task = state.get("original_task", "")
    research = state.get("research_results", [])
    tasks = []
    for r in research:
        found = re.findall(r"\[브라우저\s*필요[:\s]*([^\]]+)\]", r)
        tasks.extend(found)
    if not tasks: tasks = [task]
    results = []
    for bt in tasks[:2]:
        r = await _run_browser_task(bt)
        results.append(f"[브라우저]{r[:2000]}")
    if not results: results.append("[결과없음]")
    return {"messages": [AIMessage(content="\n---\n".join(results), name="browser")],
            "browser_results": results}
MAEOF

cat > "${AGENT_DIR}/multi_agent/summarizer.py" << 'MAEOF'
from __future__ import annotations
import logging
from typing import Any
from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from .state import AgentState
from .groq_utils import invoke_retry, model_config, trunc_list, prep_ctx

logger = logging.getLogger("multi_agent.summarizer")
PROMPT=("수집 결과 종합→최종 답변. 비교→표, 추천→순위. 한국어 Markdown.
"
        "마지막에 [Multi-Agent 조사 완료] 표기.")

async def summarizer_node(state: AgentState) -> dict[str, Any]:
    task=state.get("original_task","")
    res=state.get("research_results",[]); bro=state.get("browser_results",[])
    tr=state.get("token_tracker")
    sr=trunc_list(res,6000); sb=trunc_list(bro,4000)
    p=[f"## 요청
{task}"]
    if sr: p.extend([f"### 조사#{i+1}
{r}" for i,r in enumerate(sr)])
    if sb: p.extend([f"### 수집#{i+1}
{b}" for i,b in enumerate(sb)])
    data="

".join(p)
    mn=model_config.name("summarizer"); data,_=prep_ctx(PROMPT,data,mn,"summarizer")
    llm=model_config.get_llm("summarizer")
    msgs=[SystemMessage(content=PROMPT),HumanMessage(content=data)]
    try:
        r=await invoke_retry(llm,msgs,retries=4,node="summarizer",tracker=tr)
        return {"messages":[AIMessage(content=r.content.strip(),name="summarizer")],"next":"END"}
    except Exception as e:
        return {"messages":[AIMessage(content=f"오류:{e}",name="summarizer")],"next":"END"}
MAEOF

cat > "${AGENT_DIR}/multi_agent/graph.py" << 'MAEOF'
from __future__ import annotations
import asyncio, logging, re
from typing import Any
from langgraph.graph import END, StateGraph
from .state import AgentState
from .supervisor import supervisor_node
from .research_agent import research_node
from .browser_tool_agent import browser_node
from .summarizer import summarizer_node

logger = logging.getLogger("multi_agent.graph")
WT = 300

def _route(s):
    n=s.get("next","END")
    return n if n in ("research","browser","summarizer") else "END"

def build_graph():
    g=StateGraph(AgentState)
    g.add_node("supervisor",supervisor_node); g.add_node("research",research_node)
    g.add_node("browser",browser_node); g.add_node("summarizer",summarizer_node)
    g.set_entry_point("supervisor")
    g.add_conditional_edges("supervisor",_route,
        {"research":"research","browser":"browser","summarizer":"summarizer","END":END})
    g.add_edge("research","supervisor"); g.add_edge("browser","supervisor")
    g.add_edge("summarizer",END)
    return g.compile()

_graph = None
def _get_graph():
    global _graph
    if _graph is None: _graph = build_graph()
    return _graph

async def run_multi_agent(task, model="llama-3.3-70b-versatile", budget_usd=0.0):
    from langchain_core.messages import HumanMessage
    from .groq_utils import TokenTracker
    graph=_get_graph(); tracker=TokenTracker(budget=budget_usd)
    san=re.sub(r'\{\s*"lc"\s*:\s*\d','{"_lc":0',task[:4096].replace("\x00","")).strip()
    st={"messages":[HumanMessage(content=san)],"next":"","original_task":san,
        "research_results":[],"browser_results":[],"iteration":0,"route_history":[],
        "model":model,"token_tracker":tracker}
    try:
        r=await asyncio.wait_for(graph.ainvoke(st),timeout=WT)
        ms=r.get("messages",[])
        return {"response":ms[-1].content if ms else "응답없음","iterations":r.get("iteration",0),
                "research_count":len(r.get("research_results",[])),"browser_count":len(r.get("browser_results",[])),
                "token_usage":tracker.summary}
    except asyncio.TimeoutError:
        return {"response":f"⏱️ {WT}초 타임아웃","iterations":0,"research_count":0,"browser_count":0,"token_usage":tracker.summary}
    except Exception as e:
        return {"response":f"❌ 오류: {e}","iterations":0,"research_count":0,"browser_count":0,"token_usage":tracker.summary}
MAEOF

ok "FILE 4.5/7  Multi-Agent 모듈 (7개 파일)"


# ── FILE 5: openwebui_tool.py (base64 — CRLF/heredoc 오류 방지) ────────
AGENT_DIR="${AGENT_DIR}" python3 << 'WRITE_TOOL'
import base64, os
b64 = (
    "IiIiCnRpdGxlOiBBSSDruIzrnbzsmrDsoIAg7JeQ7J207KCE7Yq4CmF1dGhvcjogT3BlbldlYlVJ"
    "CnZlcnNpb246IDYuNC4wCiIiIgppbXBvcnQgb3MsIHVybGxpYi5wYXJzZSwgdGltZQpmcm9tIHR5"
    "cGluZyBpbXBvcnQgQW55LCBDYWxsYWJsZSwgT3B0aW9uYWwsIERpY3QKZnJvbSBweWRhbnRpYyBp"
    "bXBvcnQgQmFzZU1vZGVsLCBGaWVsZAoKY2xhc3MgVG9vbHM6CiAgICBjbGFzcyBWYWx2ZXMoQmFz"
    "ZU1vZGVsKToKICAgICAgICBCUk9XU0VSX0FHRU5UX1VSTDogc3RyID0gRmllbGQoZGVmYXVsdD0i"
    "aHR0cDovL2Jyb3dzZXItYWdlbnQ6ODAwMSIsIGRlc2NyaXB0aW9uPSJCcm93c2VyIEFnZW50IOyE"
    "nOuyhCBVUkwiKQogICAgICAgIEJST1dTRVJfQUdFTlRfQVBJX0tFWTogc3RyID0gRmllbGQoZGVm"
    "YXVsdD0iIiwgZGVzY3JpcHRpb249IkJyb3dzZXIgQWdlbnQgQVBJIO2CpCAo67mE7JuM65GQ66m0"
    "IOyduOymnSDsl4bsnbQg7KCR7IaNKSIpCiAgICAgICAgTExNX1BST1ZJREVSOiBzdHIgPSBGaWVs"
    "ZChkZWZhdWx0PSJncm9xIiwgZGVzY3JpcHRpb249IkxMTSDtlITroZzrsJTsnbTrjZQ6IGdyb3Eg"
    "LyBvcGVuYWkgLyBhbnRocm9waWMgLyBnb29nbGUiKQogICAgICAgIExMTV9BUElfS0VZOiBzdHIg"
    "PSBGaWVsZChkZWZhdWx0PSIiLCBkZXNjcmlwdGlvbj0iTExNIEFQSSDtgqQgKOu5hOybjOuRkOup"
    "tCDshJzrsoQgLmVudiDtgqQg7IKs7JqpKSIpCiAgICAgICAgTExNX01PREVMOiBzdHIgPSBGaWVs"
    "ZChkZWZhdWx0PSIiLCBkZXNjcmlwdGlvbj0i66qo642466qFICjruYTsm4zrkZDrqbQg6riw67O4"
    "6rCSKSIpCiAgICAgICAgREVGQVVMVF9NQVhfU1RFUFM6IGludCA9IEZpZWxkKGRlZmF1bHQ9MTUs"
    "IGRlc2NyaXB0aW9uPSLstZzrjIAg7Iuk7ZaJIOuLqOqzhCDsiJgiKQogICAgICAgIFJFUVVFU1Rf"
    "VElNRU9VVDogaW50ID0gRmllbGQoZGVmYXVsdD0yMDAsIGRlc2NyaXB0aW9uPSLsmpTssq0g7YOA"
    "7J6E7JWE7JuDICjstIgpIikKICAgICAgICBFTkFCTEVfTUVNT1JZOiBib29sID0gRmllbGQoZGVm"
    "YXVsdD1UcnVlLCBkZXNjcmlwdGlvbj0i66mU66qo66asL+2VmeyKtSDquLDriqUiKQogICAgICAg"
    "IEVOQUJMRV9GSUxFX0FDQ0VTUzogYm9vbCA9IEZpZWxkKGRlZmF1bHQ9VHJ1ZSwgZGVzY3JpcHRp"
    "b249IuuhnOy7rCDtjIzsnbwg7KCR6re8ICh+L2FpLXNoYXJlKSIpCiAgICAgICAgRU5BQkxFX01V"
    "TFRJVEFCOiBib29sID0gRmllbGQoZGVmYXVsdD1UcnVlLCBkZXNjcmlwdGlvbj0i66mA7Yuw7YOt"
    "IOu5hOq1kCAo7Jyg66OMIEFQSSDqtozsnqUpIikKICAgICAgICBNQVhfVEFCUzogaW50ID0gRmll"
    "bGQoZGVmYXVsdD0zLCBkZXNjcmlwdGlvbj0i66mA7Yuw7YOtIOy1nOuMgCDsiJggKDF+NSkiKQog"
    "ICAgICAgIENBQ0hFX1RUTDogaW50ID0gRmllbGQoZGVmYXVsdD0zMDAsIGRlc2NyaXB0aW9uPSLs"
    "upDsi5wg7Jyg7ZqoIOyLnOqwhCAo7LSILCAwPeu5hO2ZnOyEse2ZlCkiKQoKICAgIGRlZiBfX2lu"
    "aXRfXyhzZWxmKToKICAgICAgICBzZWxmLnZhbHZlcyA9IHNlbGYuVmFsdmVzKCkKICAgICAgICBz"
    "ZWxmLl9zZXNzaW9uX2lkOiBPcHRpb25hbFtzdHJdID0gTm9uZQogICAgICAgIHNlbGYuX2NhY2hl"
    "OiBEaWN0W3N0ciwgZGljdF0gPSB7fQoKICAgIGRlZiBfaGVhZGVycyhzZWxmKSAtPiBkaWN0Ogog"
    "ICAgICAgIGhlYWRlcnMgPSB7IkNvbnRlbnQtVHlwZSI6ICJhcHBsaWNhdGlvbi9qc29uIn0KICAg"
    "ICAgICBpZiBzZWxmLnZhbHZlcy5CUk9XU0VSX0FHRU5UX0FQSV9LRVk6CiAgICAgICAgICAgIGhl"
    "YWRlcnNbIkF1dGhvcml6YXRpb24iXSA9IGYiQmVhcmVyIHtzZWxmLnZhbHZlcy5CUk9XU0VSX0FH"
    "RU5UX0FQSV9LRVl9IgogICAgICAgIHJldHVybiBoZWFkZXJzCgogICAgZGVmIF9nZXRfY2FjaGUo"
    "c2VsZiwga2V5KToKICAgICAgICBpZiBzZWxmLnZhbHZlcy5DQUNIRV9UVEwgPD0gMDogcmV0dXJu"
    "IE5vbmUKICAgICAgICBlbnRyeSA9IHNlbGYuX2NhY2hlLmdldChrZXkpCiAgICAgICAgaWYgZW50"
    "cnkgYW5kIHRpbWUudGltZSgpIC0gZW50cnlbInRzIl0gPCBzZWxmLnZhbHZlcy5DQUNIRV9UVEw6"
    "IHJldHVybiBlbnRyeVsiZGF0YSJdCiAgICAgICAgcmV0dXJuIE5vbmUKCiAgICBkZWYgX3NldF9j"
    "YWNoZShzZWxmLCBrZXksIGRhdGEpOgogICAgICAgIGlmIHNlbGYudmFsdmVzLkNBQ0hFX1RUTCA+"
    "IDA6CiAgICAgICAgICAgIHNlbGYuX2NhY2hlW2tleV0gPSB7ImRhdGEiOiBkYXRhLCAidHMiOiB0"
    "aW1lLnRpbWUoKX0KICAgICAgICAgICAgaWYgbGVuKHNlbGYuX2NhY2hlKSA+IDUwOgogICAgICAg"
    "ICAgICAgICAgb2xkZXN0ID0gbWluKHNlbGYuX2NhY2hlLCBrZXk9bGFtYmRhIGs6IHNlbGYuX2Nh"
    "Y2hlW2tdWyJ0cyJdKQogICAgICAgICAgICAgICAgZGVsIHNlbGYuX2NhY2hlW29sZGVzdF0KCiAg"
    "ICBhc3luYyBkZWYgX3Bvc3Qoc2VsZiwgcGF0aCwgcGF5bG9hZCk6CiAgICAgICAgaW1wb3J0IGh0"
    "dHB4CiAgICAgICAgaWYgaXNpbnN0YW5jZShwYXlsb2FkLCBkaWN0KToKICAgICAgICAgICAgaWYg"
    "c2VsZi52YWx2ZXMuTExNX1BST1ZJREVSOiBwYXlsb2FkLnNldGRlZmF1bHQoInByb3ZpZGVyIiwg"
    "c2VsZi52YWx2ZXMuTExNX1BST1ZJREVSKQogICAgICAgICAgICBpZiBzZWxmLnZhbHZlcy5MTE1f"
    "QVBJX0tFWTogcGF5bG9hZC5zZXRkZWZhdWx0KCJhcGlfa2V5Iiwgc2VsZi52YWx2ZXMuTExNX0FQ"
    "SV9LRVkpCiAgICAgICAgICAgIGlmIHNlbGYudmFsdmVzLkxMTV9NT0RFTDogcGF5bG9hZC5zZXRk"
    "ZWZhdWx0KCJtb2RlbCIsIHNlbGYudmFsdmVzLkxMTV9NT0RFTCkKICAgICAgICB1cmwgPSBzZWxm"
    "LnZhbHZlcy5CUk9XU0VSX0FHRU5UX1VSTC5yc3RyaXAoIi8iKSArIHBhdGgKICAgICAgICBhc3lu"
    "YyB3aXRoIGh0dHB4LkFzeW5jQ2xpZW50KHRpbWVvdXQ9c2VsZi52YWx2ZXMuUkVRVUVTVF9USU1F"
    "T1VUKSBhcyBjOgogICAgICAgICAgICByID0gYXdhaXQgYy5wb3N0KHVybCwganNvbj1wYXlsb2Fk"
    "LCBoZWFkZXJzPXNlbGYuX2hlYWRlcnMoKSkKICAgICAgICAgICAgaWYgci5zdGF0dXNfY29kZSA9"
    "PSA0MDE6IHJhaXNlIFBlcm1pc3Npb25FcnJvcigiQVBJIO2CpCDsnbjspp0g7Iuk7YyoIikKICAg"
    "ICAgICAgICAgaWYgci5zdGF0dXNfY29kZSA9PSA0MDM6IHJhaXNlIFBlcm1pc3Npb25FcnJvcigi"
    "7KCR6re8IOqxsOu2gCIpCiAgICAgICAgICAgIGlmIHIuc3RhdHVzX2NvZGUgPT0gNDI5OiByYWlz"
    "ZSBSdW50aW1lRXJyb3IoIuyalOyyrSDtlZzrj4Qg7LSI6rO8IikKICAgICAgICAgICAgci5yYWlz"
    "ZV9mb3Jfc3RhdHVzKCkKICAgICAgICAgICAgZGF0YSA9IHIuanNvbigpCiAgICAgICAgICAgIGlm"
    "IGlzaW5zdGFuY2UoZGF0YSwgZGljdCkgYW5kIGRhdGEuZ2V0KCJzdWNjZXNzIikgaXMgRmFsc2U6"
    "CiAgICAgICAgICAgICAgICByYWlzZSBSdW50aW1lRXJyb3IoIuu4jOudvOyasOyggCDsl5DsnbTs"
    "oITtirgg7Jik66WYOiAiICsgZGF0YS5nZXQoImVycm9yIiwgIiIpKQogICAgICAgICAgICByZXR1"
    "cm4gZGF0YQoKICAgIGFzeW5jIGRlZiBicm93c2Uoc2VsZiwgdGFzaywgX19ldmVudF9lbWl0dGVy"
    "X189Tm9uZSk6CiAgICAgICAgIiIiT3BlbiBhIFVSTCBhbmQgcGVyZm9ybSBhIHRhc2suIERvIE5P"
    "VCB1c2UgZm9yIHdlYXRoZXIvcHJpY2VzL3N0b2NrcyAtIHVzZSBkZWRpY2F0ZWQgZnVuY3Rpb25z"
    "LgogICAgICAgIDpwYXJhbSB0YXNrOiBVUkwgKyBpbnN0cnVjdGlvbgogICAgICAgICIiIgogICAg"
    "ICAgIGFzeW5jIGRlZiBlbWl0KG1zZywgZG9uZT1GYWxzZSk6CiAgICAgICAgICAgIGlmIF9fZXZl"
    "bnRfZW1pdHRlcl9fOiBhd2FpdCBfX2V2ZW50X2VtaXR0ZXJfXyh7InR5cGUiOiJzdGF0dXMiLCJk"
    "YXRhIjp7ImRlc2NyaXB0aW9uIjptc2csImRvbmUiOmRvbmV9fSkKICAgICAgICBpZiBsZW4odGFz"
    "ay5zdHJpcCgpKSA8IDI6IHJldHVybiAi7J6R7JeFIOuCtOyaqeydtCDrhIjrrLQg7Ken7Iq164uI"
    "64ukLiIKICAgICAgICBhd2FpdCBlbWl0KCLruIzrnbzsmrDsoIDrpbwg7Je06rOgIOyekeyXhSDs"
    "pJEuLi4iKQogICAgICAgIHRyeToKICAgICAgICAgICAgcmVzdWx0ID0gYXdhaXQgc2VsZi5fcG9z"
    "dCgiL2Jyb3dzZSIsIHsidGFzayI6IHRhc2ssICJtYXhfc3RlcHMiOiBzZWxmLnZhbHZlcy5ERUZB"
    "VUxUX01BWF9TVEVQU30pCiAgICAgICAgICAgIGF3YWl0IGVtaXQoIuyZhOujjCEiLCBkb25lPVRy"
    "dWUpCiAgICAgICAgICAgIHJldHVybiByZXN1bHQuZ2V0KCJzdW1tYXJ5X3BsYWluIikgb3IgcmVz"
    "dWx0LmdldCgic3VtbWFyeSIsICLsnpHsl4Ug7JmE66OMIikKICAgICAgICBleGNlcHQgRXhjZXB0"
    "aW9uIGFzIGU6CiAgICAgICAgICAgIGF3YWl0IGVtaXQoIuyYpOulmCIsIGRvbmU9VHJ1ZSkKICAg"
    "ICAgICAgICAgcmV0dXJuIGYi7Jik66WYOiB7ZX0iCgogICAgYXN5bmMgZGVmIF9uYXZlcl9zZWFy"
    "Y2goc2VsZiwgcXVlcnlfa3IsIGluc3RydWN0aW9uLCBfX2V2ZW50X2VtaXR0ZXJfXz1Ob25lKToK"
    "ICAgICAgICBjYWNoZWQgPSBzZWxmLl9nZXRfY2FjaGUoInNlYXJjaDoiICsgcXVlcnlfa3IpCiAg"
    "ICAgICAgaWYgY2FjaGVkOiByZXR1cm4gY2FjaGVkCiAgICAgICAgZW5jb2RlZCA9IHVybGxpYi5w"
    "YXJzZS5xdW90ZShxdWVyeV9rcikKICAgICAgICB1cmwgPSAiaHR0cHM6Ly9zZWFyY2gubmF2ZXIu"
    "Y29tL3NlYXJjaC5uYXZlcj9xdWVyeT0iICsgZW5jb2RlZAogICAgICAgIHJlc3VsdCA9IGF3YWl0"
    "IHNlbGYuYnJvd3NlKHVybCArICIgIiArIGluc3RydWN0aW9uLCBfX2V2ZW50X2VtaXR0ZXJfXykK"
    "ICAgICAgICBpZiAi6rKA7IOJIOqysOqzvCDsl4bsnYwiIGluIHJlc3VsdCBvciAiQ0FQVENIQSIg"
    "aW4gcmVzdWx0OgogICAgICAgICAgICByZXN1bHQgPSBhd2FpdCBzZWxmLmJyb3dzZSgiaHR0cHM6"
    "Ly9zZWFyY2guZGF1bS5uZXQvc2VhcmNoP3E9IiArIGVuY29kZWQgKyAiICIgKyBpbnN0cnVjdGlv"
    "biwgX19ldmVudF9lbWl0dGVyX18pCiAgICAgICAgc2VsZi5fc2V0X2NhY2hlKCJzZWFyY2g6IiAr"
    "IHF1ZXJ5X2tyLCByZXN1bHQpCiAgICAgICAgcmV0dXJuIHJlc3VsdAoKICAgIGRlZiBfdHJhbnNs"
    "YXRlX2tleXdvcmQoc2VsZiwga2V5d29yZCwga2V5d29yZF9tYXApOgogICAgICAgIGt3ID0ga2V5"
    "d29yZC5sb3dlcigpLnN0cmlwKCkKICAgICAgICBpZiBrdyBpbiBrZXl3b3JkX21hcDogcmV0dXJu"
    "IGtleXdvcmRfbWFwW2t3XQogICAgICAgIGZvciBlbmcsIGtvciBpbiBzb3J0ZWQoa2V5d29yZF9t"
    "YXAuaXRlbXMoKSwga2V5PWxhbWJkYSB4OiAtbGVuKHhbMF0pKToKICAgICAgICAgICAgaWYgZW5n"
    "IGluIGt3OiByZXR1cm4ga3cucmVwbGFjZShlbmcsIGtvcikKICAgICAgICByZXR1cm4ga2V5d29y"
    "ZAoKICAgIGFzeW5jIGRlZiBzZWFyY2hfbmF2ZXIoc2VsZiwga2V5d29yZCwgX19ldmVudF9lbWl0"
    "dGVyX189Tm9uZSk6CiAgICAgICAgIiIiU2VhcmNoIE5hdmVyIGZvciByZWFsLXRpbWUgaW5mb3Jt"
    "YXRpb24uCiAgICAgICAgOnBhcmFtIGtleXdvcmQ6IFNlYXJjaCBrZXl3b3JkCiAgICAgICAgIiIi"
    "CiAgICAgICAgaWYgbm90IGtleXdvcmQuc3RyaXAoKTogcmV0dXJuICLqsoDsg4nslrTrpbwg7J6F"
    "66Cl7ZWY7IS47JqULiIKICAgICAgICBrbSA9IHsid2VhdGhlciI6IuuCoOyUqCIsIm5ld3MiOiLr"
    "ibTsiqQiLCJzdG9jayI6IuyjvOqwgCIsImV4Y2hhbmdlIHJhdGUiOiLtmZjsnKgiLCJwcmljZSI6"
    "IuqwgOqyqSIsCiAgICAgICAgICAgICAgImJpdGNvaW4iOiLruYTtirjsvZTsnbgiLCJzb2NjZXIi"
    "OiLstpXqtawiLCJiYXNlYmFsbCI6IuyVvOq1rCIsIm1vdmllIjoi7JiB7ZmUIiwidHJhdmVsIjoi"
    "7Jes7ZaJIn0KICAgICAgICByZXR1cm4gYXdhaXQgc2VsZi5fbmF2ZXJfc2VhcmNoKHNlbGYuX3Ry"
    "YW5zbGF0ZV9rZXl3b3JkKGtleXdvcmQsIGttKSwKICAgICAgICAgICAgInJlYWQgdGhlIGtleSBp"
    "bmZvcm1hdGlvbiBmcm9tIHNlYXJjaCByZXN1bHRzIGluIEtvcmVhbiIsIF9fZXZlbnRfZW1pdHRl"
    "cl9fKQoKICAgIGFzeW5jIGRlZiBjaGVja193ZWF0aGVyKHNlbGYsIF9fZXZlbnRfZW1pdHRlcl9f"
    "PU5vbmUpOgogICAgICAgICIiIkNoZWNrIHRvZGF5J3Mgd2VhdGhlciBmcm9tIE5hdmVyLiBVc2Ug"
    "Zm9yIHdlYXRoZXIsIHRlbXBlcmF0dXJlLCByYWluLCB1bWJyZWxsYSwgZmluZSBkdXN0IHF1ZXN0"
    "aW9ucy4iIiIKICAgICAgICBjYWNoZWQgPSBzZWxmLl9nZXRfY2FjaGUoIndlYXRoZXI6dG9kYXki"
    "KQogICAgICAgIGlmIGNhY2hlZDogcmV0dXJuIGNhY2hlZAogICAgICAgIGFzeW5jIGRlZiBlbWl0"
    "KG1zZywgZG9uZT1GYWxzZSk6CiAgICAgICAgICAgIGlmIF9fZXZlbnRfZW1pdHRlcl9fOiBhd2Fp"
    "dCBfX2V2ZW50X2VtaXR0ZXJfXyh7InR5cGUiOiJzdGF0dXMiLCJkYXRhIjp7ImRlc2NyaXB0aW9u"
    "Ijptc2csImRvbmUiOmRvbmV9fSkKICAgICAgICBhd2FpdCBlbWl0KCLrgqDslKgg7ZmV7J24IOyk"
    "kS4uLiIpCiAgICAgICAgdHJ5OgogICAgICAgICAgICByZXN1bHQgPSBhd2FpdCBzZWxmLl9wb3N0"
    "KCIvYnJvd3NlIiwgewogICAgICAgICAgICAgICAgInRhc2siOiAiaHR0cHM6Ly9zZWFyY2gubmF2"
    "ZXIuY29tL3NlYXJjaC5uYXZlcj9xdWVyeT3shJzsmrgr64Kg7JSoIHJlYWQgY3VycmVudCB3ZWF0"
    "aGVyOiB0ZW1wZXJhdHVyZSwgY29uZGl0aW9uLCBmaW5lIGR1c3QsIFVWIGluZGV4LiBSZXNwb25k"
    "IGluIEtvcmVhbi4iLAogICAgICAgICAgICAgICAgIm1heF9zdGVwcyI6IDh9KQogICAgICAgICAg"
    "ICB3ZWF0aGVyID0gcmVzdWx0LmdldCgic3VtbWFyeV9wbGFpbiIpIG9yIHJlc3VsdC5nZXQoInN1"
    "bW1hcnkiLCAiIikKICAgICAgICAgICAgYXdhaXQgZW1pdCgi7JmE66OMISIsIGRvbmU9VHJ1ZSkK"
    "ICAgICAgICAgICAgaWYgd2VhdGhlcjogc2VsZi5fc2V0X2NhY2hlKCJ3ZWF0aGVyOnRvZGF5Iiwg"
    "d2VhdGhlcikKICAgICAgICAgICAgcmV0dXJuIHdlYXRoZXIgb3IgIuuCoOyUqCDsoJXrs7Trpbwg"
    "6rCA7KC47Jik7KeAIOuqu+2WiOyKteuLiOuLpC4iCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBh"
    "cyBlOgogICAgICAgICAgICBhd2FpdCBlbWl0KCLsmKTrpZgiLCBkb25lPVRydWUpCiAgICAgICAg"
    "ICAgIHJldHVybiAi64Kg7JSoIO2ZleyduCDsmKTrpZg6ICIgKyBzdHIoZSkKCiAgICBhc3luYyBk"
    "ZWYgY2hlY2tfcHJpY2Uoc2VsZiwgcHJvZHVjdCwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAg"
    "ICAgICAgIiIiU2VhcmNoIHByb2R1Y3QgcHJpY2VzIG9uIE5hdmVyIFNob3BwaW5nLgogICAgICAg"
    "IDpwYXJhbSBwcm9kdWN0OiBQcm9kdWN0IG5hbWUKICAgICAgICAiIiIKICAgICAgICBpZiBub3Qg"
    "cHJvZHVjdC5zdHJpcCgpOiByZXR1cm4gIuyDge2SiOuqheydhCDsnoXroKXtlZjshLjsmpQuIgog"
    "ICAgICAgIHBtID0geyJhaXJwb2RzIjoi7JeQ7Ja07YyfIiwiYWlycG9kcyBwcm8iOiLsl5DslrTt"
    "jJ8g7ZSE66GcIiwiaXBob25lIjoi7JWE7J207Y+wIiwiZ2FsYXh5Ijoi6rCk65+t7IucIiwKICAg"
    "ICAgICAgICAgICAibWFjYm9vayI6Iuunpeu2gSIsImlwYWQiOiLslYTsnbTtjKjrk5wiLCJuaW50"
    "ZW5kbyBzd2l0Y2giOiLri4zthZDrj4Qg7Iqk7JyE7LmYIiwicHM1Ijoi7ZSM66CI7J207Iqk7YWM"
    "7J207IWYNSJ9CiAgICAgICAgcmV0dXJuIGF3YWl0IHNlbGYuX25hdmVyX3NlYXJjaChzZWxmLl90"
    "cmFuc2xhdGVfa2V5d29yZChwcm9kdWN0LCBwbSkgKyAiIOqwgOqyqSIsCiAgICAgICAgICAgICJm"
    "aW5kIGxvd2VzdCBwcmljZSwgc3RvcmUgbmFtZSwgZGVsaXZlcnkgaW5mby4gUmVzcG9uZCBpbiBL"
    "b3JlYW4uIiwgX19ldmVudF9lbWl0dGVyX18pCgogICAgYXN5bmMgZGVmIGNoZWNrX3N0b2NrKHNl"
    "bGYsIGNvbXBhbnksIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIkNoZWNrIHN0"
    "b2NrIHByaWNlIGFuZCBtYXJrZXQgZGF0YS4KICAgICAgICA6cGFyYW0gY29tcGFueTogQ29tcGFu"
    "eSBuYW1lCiAgICAgICAgIiIiCiAgICAgICAgaWYgbm90IGNvbXBhbnkuc3RyaXAoKTogcmV0dXJu"
    "ICLtmozsgqzrqoXsnYQg7J6F66Cl7ZWY7IS47JqULiIKICAgICAgICBzbSA9IHsic2Ftc3VuZyI6"
    "IuyCvOyEseyghOyekCIsInNrIGh5bml4IjoiU0vtlZjsnbTri4nsiqQiLCJhcHBsZSI6IuyVoO2U"
    "jCDso7zqsIAiLCJudmlkaWEiOiLsl5TruYTrlJTslYQg7KO86rCAIiwKICAgICAgICAgICAgICAi"
    "dGVzbGEiOiLthYzsiqzrnbwg7KO86rCAIiwia29zcGkiOiLsvZTsiqTtlLwiLCJrb3NkYXEiOiLs"
    "vZTsiqTri6UiLCJuYXNkYXEiOiLrgpjsiqTri6UifQogICAgICAgIGsgPSBzZWxmLl90cmFuc2xh"
    "dGVfa2V5d29yZChjb21wYW55LCBzbSkKICAgICAgICBpZiAi7KO86rCAIiBub3QgaW4gayBhbmQg"
    "ayBub3QgaW4gWyLsvZTsiqTtlLwiLCLsvZTsiqTri6UiLCLrgpjsiqTri6UiXTogayArPSAiIOyj"
    "vOqwgCIKICAgICAgICByZXR1cm4gYXdhaXQgc2VsZi5fbmF2ZXJfc2VhcmNoKGssICJyZWFkIHN0"
    "b2NrIHByaWNlLCBjaGFuZ2UsIG1hcmtldCBjYXAuIFJlc3BvbmQgaW4gS29yZWFuLiIsIF9fZXZl"
    "bnRfZW1pdHRlcl9fKQoKICAgIGFzeW5jIGRlZiBjaGVja19uZXdzKHNlbGYsIF9fZXZlbnRfZW1p"
    "dHRlcl9fPU5vbmUpOgogICAgICAgICIiIkNoZWNrIHRvZGF5J3MgdG9wIG5ld3MgaGVhZGxpbmVz"
    "IGZyb20gTmF2ZXIgTmV3cy4iIiIKICAgICAgICBjYWNoZWQgPSBzZWxmLl9nZXRfY2FjaGUoIm5l"
    "d3M6dG9kYXkiKQogICAgICAgIGlmIGNhY2hlZDogcmV0dXJuIGNhY2hlZAogICAgICAgIHJlc3Vs"
    "dCA9IGF3YWl0IHNlbGYuYnJvd3NlKCJodHRwczovL25ld3MubmF2ZXIuY29tIGxpc3QgdG9wIDUg"
    "bmV3cyBoZWFkbGluZXMgaW4gS29yZWFuLiIsIF9fZXZlbnRfZW1pdHRlcl9fKQogICAgICAgIHNl"
    "bGYuX3NldF9jYWNoZSgibmV3czp0b2RheSIsIHJlc3VsdCkKICAgICAgICByZXR1cm4gcmVzdWx0"
    "CgogICAgYXN5bmMgZGVmIGNoZWNrX2V4Y2hhbmdlX3JhdGUoc2VsZiwgY3VycmVuY3k9ImRvbGxh"
    "ciIsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIkNoZWNrIGN1cnJlbnQgZXhj"
    "aGFuZ2UgcmF0ZXMuCiAgICAgICAgOnBhcmFtIGN1cnJlbmN5OiBDdXJyZW5jeSBuYW1lIChkb2xs"
    "YXIsIHllbiwgZXVybywgeXVhbikKICAgICAgICAiIiIKICAgICAgICBybSA9IHsiZG9sbGFyIjoi"
    "64us65+sIO2ZmOycqCIsInVzZCI6IuuLrOufrCDtmZjsnKgiLCJ5ZW4iOiLsl5TtmZQg7ZmY7Jyo"
    "IiwiZXVybyI6IuycoOuhnCDtmZjsnKgiLCJ5dWFuIjoi7JyE7JWIIO2ZmOycqCIsInBvdW5kIjoi"
    "7YyM7Jq065OcIO2ZmOycqCJ9CiAgICAgICAgcmV0dXJuIGF3YWl0IHNlbGYuX25hdmVyX3NlYXJj"
    "aChzZWxmLl90cmFuc2xhdGVfa2V5d29yZChjdXJyZW5jeSwgcm0pLAogICAgICAgICAgICAicmVh"
    "ZCBleGNoYW5nZSByYXRlLCBjaGFuZ2UgZnJvbSB5ZXN0ZXJkYXkuIFJlc3BvbmQgaW4gS29yZWFu"
    "LiIsIF9fZXZlbnRfZW1pdHRlcl9fKQoKICAgIGFzeW5jIGRlZiBjaGVja19zcG9ydHMoc2VsZiwg"
    "c3BvcnQ9InNvY2NlciIsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIkNoZWNr"
    "IHNwb3J0cyBzY29yZXMgYW5kIHJlc3VsdHMuCiAgICAgICAgOnBhcmFtIHNwb3J0OiBTcG9ydCB0"
    "eXBlIChzb2NjZXIsIGJhc2ViYWxsLCBiYXNrZXRiYWxsLCBrYm8sIGVwbCkKICAgICAgICAiIiIK"
    "ICAgICAgICBzbSA9IHsic29jY2VyIjoi7LaV6rWsIOqyveq4sOqysOqzvCIsImJhc2ViYWxsIjoi"
    "7JW86rWsIOqyveq4sOqysOqzvCIsImJhc2tldGJhbGwiOiLrho3qtawg6rK96riw6rKw6rO8IiwK"
    "ICAgICAgICAgICAgICAia2JvIjoiS0JPIOqyveq4sOqysOqzvCIsImVwbCI6IkVQTCDqsrDqs7wi"
    "LCJuYmEiOiJOQkEg6rKw6rO8In0KICAgICAgICByZXR1cm4gYXdhaXQgc2VsZi5fbmF2ZXJfc2Vh"
    "cmNoKHNlbGYuX3RyYW5zbGF0ZV9rZXl3b3JkKHNwb3J0LCBzbSksCiAgICAgICAgICAgICJyZWFk"
    "IHJlY2VudCBtYXRjaCByZXN1bHRzLCBzY29yZXMsIHN0YW5kaW5ncy4gUmVzcG9uZCBpbiBLb3Jl"
    "YW4uIiwgX19ldmVudF9lbWl0dGVyX18pCgogICAgYXN5bmMgZGVmIHN1bW1hcml6ZV95b3V0dWJl"
    "KHNlbGYsIHVybCwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiU3VtbWFyaXpl"
    "IGEgWW91VHViZSB2aWRlby4KICAgICAgICA6cGFyYW0gdXJsOiBZb3VUdWJlIFVSTAogICAgICAg"
    "ICIiIgogICAgICAgIGlmICJ5b3V0dWJlLmNvbSIgbm90IGluIHVybCBhbmQgInlvdXR1LmJlIiBu"
    "b3QgaW4gdXJsOiByZXR1cm4gIllvdVR1YmUgVVJM7J20IOyVhOuLmeuLiOuLpC4iCiAgICAgICAg"
    "cmV0dXJuIGF3YWl0IHNlbGYuYnJvd3NlKHVybCArICIgc3VtbWFyaXplIHZpZGVvIHRpdGxlLCBj"
    "aGFubmVsLCB2aWV3IGNvdW50LCBtYWluIGNvbnRlbnQgaW4gS29yZWFuLiIsIF9fZXZlbnRfZW1p"
    "dHRlcl9fKQoKICAgIGFzeW5jIGRlZiBvcGVuX2FuZF9zdW1tYXJpemUoc2VsZiwgdXJsLCBfX2V2"
    "ZW50X2VtaXR0ZXJfXz1Ob25lKToKICAgICAgICAiIiJPcGVuIGEgd2VicGFnZSBhbmQgc3VtbWFy"
    "aXplIGluIEtvcmVhbi4KICAgICAgICA6cGFyYW0gdXJsOiBGdWxsIFVSTAogICAgICAgICIiIgog"
    "ICAgICAgIGlmIG5vdCB1cmwuc3RhcnRzd2l0aCgoImh0dHA6Ly8iLCJodHRwczovLyIpKTogcmV0"
    "dXJuICJVUkzsnYAgaHR0cDovL+uhnCDsi5zsnpHtlbTslbwg7ZWp64uI64ukLiIKICAgICAgICBi"
    "bG9ja2VkID0gWyJjb3VwYW5nLmNvbSIsImdtYXJrZXQuY28ua3IiLCIxMXN0LmNvLmtyIiwiYXVj"
    "dGlvbi5jby5rciJdCiAgICAgICAgaWYgYW55KHMgaW4gdXJsLmxvd2VyKCkgZm9yIHMgaW4gYmxv"
    "Y2tlZCk6IHJldHVybiAi7J20IOyCrOydtO2KuOuKlCDssKjri6jrkKnri4jri6QuIGNoZWNrX3By"
    "aWNl66W8IOyCrOyaqe2VmOyEuOyalC4iCiAgICAgICAgaWYgInlvdXR1YmUuY29tIiBpbiB1cmwg"
    "b3IgInlvdXR1LmJlIiBpbiB1cmw6IHJldHVybiBhd2FpdCBzZWxmLnN1bW1hcml6ZV95b3V0dWJl"
    "KHVybCwgX19ldmVudF9lbWl0dGVyX18pCiAgICAgICAgcmV0dXJuIGF3YWl0IHNlbGYuYnJvd3Nl"
    "KHVybCArICIgc3VtbWFyaXplIHRoZSBtYWluIGNvbnRlbnQgaW4gS29yZWFuIiwgX19ldmVudF9l"
    "bWl0dGVyX18pCgogICAgYXN5bmMgZGVmIG11bHRpX2FnZW50X2Jyb3dzZShzZWxmLCB0YXNrLCBf"
    "X2V2ZW50X2VtaXR0ZXJfXz1Ob25lLCBfX3VzZXJfXz17fSk6CiAgICAgICAgIiIiTXVsdGktQWdl"
    "bnQg66qo65Oc66GcIOuzteyeoe2VnCDsnpHsl4Ug7IiY7ZaJLgogICAgICAgIDpwYXJhbSB0YXNr"
    "OiDsnpHsl4Ug64K07JqpCiAgICAgICAgIiIiCiAgICAgICAgYXN5bmMgZGVmIGVtaXQobXNnLCBk"
    "b25lPUZhbHNlKToKICAgICAgICAgICAgaWYgX19ldmVudF9lbWl0dGVyX186IGF3YWl0IF9fZXZl"
    "bnRfZW1pdHRlcl9fKHsidHlwZSI6InN0YXR1cyIsImRhdGEiOnsiZGVzY3JpcHRpb24iOm1zZywi"
    "ZG9uZSI6ZG9uZX19KQogICAgICAgIGF3YWl0IGVtaXQoIk11bHRpLUFnZW50IOyhsOyCrCDsi5zs"
    "npEuLi4iKQogICAgICAgIHRyeToKICAgICAgICAgICAgcmVzdWx0ID0gYXdhaXQgc2VsZi5fcG9z"
    "dCgiL2Jyb3dzZS9tdWx0aSIsIHsidGFzayI6IHRhc2t9KQogICAgICAgICAgICBhd2FpdCBlbWl0"
    "KCLsmYTro4wiLCBkb25lPVRydWUpCiAgICAgICAgICAgIHJldHVybiByZXN1bHQuZ2V0KCJzdW1t"
    "YXJ5IiwgcmVzdWx0LmdldCgicmVzdWx0Iiwgc3RyKHJlc3VsdCkpKQogICAgICAgIGV4Y2VwdCBF"
    "eGNlcHRpb24gYXMgZToKICAgICAgICAgICAgYXdhaXQgZW1pdCgi7Jik66WYIiwgZG9uZT1UcnVl"
    "KQogICAgICAgICAgICByZXR1cm4gIk11bHRpLUFnZW50IOyYpOulmDogIiArIHN0cihlKQoKICAg"
    "IGFzeW5jIGRlZiBjbG9zZV9icm93c2VyKHNlbGYsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgog"
    "ICAgICAgICIiIkNsb3NlIGJyb3dzZXIgc2Vzc2lvbiBhbmQgY2xlYXIgY2FjaGUuIiIiCiAgICAg"
    "ICAgc2VsZi5fc2Vzc2lvbl9pZCA9IE5vbmUKICAgICAgICBzZWxmLl9jYWNoZS5jbGVhcigpCiAg"
    "ICAgICAgcmV0dXJuICLruIzrnbzsmrDsoIAg7IS47IWYIOyiheujjCArIOy6kOyLnCDstIjquLDt"
    "mZQg7JmE66OMIgoKICAgIGFzeW5jIGRlZiBnZXRfbWVtb3J5KHNlbGYsIF9fZXZlbnRfZW1pdHRl"
    "cl9fPU5vbmUpOgogICAgICAgICIiIuyggOyepeuQnCDsgqzsmqnsnpAg7KCV67O0IOyhsO2ajC4i"
    "IiIKICAgICAgICBpZiBub3Qgc2VsZi52YWx2ZXMuRU5BQkxFX01FTU9SWTogcmV0dXJuICLrqZTr"
    "qqjrpqwg67mE7Zmc7ISx7ZmUIgogICAgICAgIHRyeToKICAgICAgICAgICAgaW1wb3J0IGh0dHB4"
    "LCBqc29uCiAgICAgICAgICAgIGFzeW5jIHdpdGggaHR0cHguQXN5bmNDbGllbnQodGltZW91dD0x"
    "MCkgYXMgYzoKICAgICAgICAgICAgICAgIHIgPSBhd2FpdCBjLmdldChzZWxmLnZhbHZlcy5CUk9X"
    "U0VSX0FHRU5UX1VSTCArICIvbWVtb3J5IiwgaGVhZGVycz1zZWxmLl9oZWFkZXJzKCkpCiAgICAg"
    "ICAgICAgICAgICByZXR1cm4gIvCfk50g66mU66qo66asOlxuIiArIGpzb24uZHVtcHMoci5qc29u"
    "KCksIGVuc3VyZV9hc2NpaT1GYWxzZSwgaW5kZW50PTIpCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlv"
    "biBhcyBlOiByZXR1cm4gIuuplOuqqOumrCDsobDtmowg7Iuk7YyoOiAiICsgc3RyKGUpCgogICAg"
    "YXN5bmMgZGVmIHVwZGF0ZV9tZW1vcnkoc2VsZiwgaW5mbywgX19ldmVudF9lbWl0dGVyX189Tm9u"
    "ZSk6CiAgICAgICAgIiIi7IKs7Jqp7J6QIOygleuztCDsoIDsnqUuCiAgICAgICAgOnBhcmFtIGlu"
    "Zm86IOq4sOyWte2VoCDsoJXrs7QKICAgICAgICAiIiIKICAgICAgICBpZiBub3Qgc2VsZi52YWx2"
    "ZXMuRU5BQkxFX01FTU9SWTogcmV0dXJuICLrqZTrqqjrpqwg67mE7Zmc7ISx7ZmUIgogICAgICAg"
    "IGJvZHkgPSB7ImZhY3RzIjogW2luZm9bOjIwMF1dfQogICAgICAgIGZvciBsb2MgaW4gWyLshJzs"
    "mrgiLCLrtoDsgrAiLCLrjIDqtawiLCLsnbjsspwiLCLqtJHso7wiLCLrjIDsoIQiLCLsmrjsgrAi"
    "LCLsoJzso7wiXToKICAgICAgICAgICAgaWYgbG9jIGluIGluZm86IGJvZHlbImxvY2F0aW9uIl0g"
    "PSBsb2M7IGJyZWFrCiAgICAgICAgdHJ5OgogICAgICAgICAgICBhd2FpdCBzZWxmLl9wb3N0KCIv"
    "bWVtb3J5IiwgYm9keSk7IHJldHVybiAi4pyFIOq4sOyWte2WiOyKteuLiOuLpDogIiArIGluZm8K"
    "ICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6IHJldHVybiAi7KCA7J6lIOyLpO2MqDogIiAr"
    "IHN0cihlKQoKICAgIGFzeW5jIGRlZiBjbGVhcl9tZW1vcnkoc2VsZiwgX19ldmVudF9lbWl0dGVy"
    "X189Tm9uZSk6CiAgICAgICAgIiIi7KCA7J6l65CcIOuqqOuToCDrqZTrqqjrpqwg7IKt7KCcLiIi"
    "IgogICAgICAgIHRyeToKICAgICAgICAgICAgaW1wb3J0IGh0dHB4CiAgICAgICAgICAgIGFzeW5j"
    "IHdpdGggaHR0cHguQXN5bmNDbGllbnQodGltZW91dD0xMCkgYXMgYzoKICAgICAgICAgICAgICAg"
    "IGF3YWl0IGMuZGVsZXRlKHNlbGYudmFsdmVzLkJST1dTRVJfQUdFTlRfVVJMICsgIi9tZW1vcnki"
    "LCBoZWFkZXJzPXNlbGYuX2hlYWRlcnMoKSkKICAgICAgICAgICAgICAgIHJldHVybiAi4pyFIOup"
    "lOuqqOumrCDstIjquLDtmZQg7JmE66OMIgogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZTog"
    "cmV0dXJuICLsgq3soJwg7Iuk7YyoOiAiICsgc3RyKGUpCgogICAgYXN5bmMgZGVmIGxpc3RfZmls"
    "ZXMoc2VsZiwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIifi9haS1zaGFyZSDt"
    "j7TrjZTsnZgg7YyM7J28IOuqqeuhnSDsobDtmowuIiIiCiAgICAgICAgaWYgbm90IHNlbGYudmFs"
    "dmVzLkVOQUJMRV9GSUxFX0FDQ0VTUzogcmV0dXJuICLtjIzsnbwg7KCR6re8IOu5hO2ZnOyEse2Z"
    "lCIKICAgICAgICB0cnk6CiAgICAgICAgICAgIGltcG9ydCBodHRweAogICAgICAgICAgICBhc3lu"
    "YyB3aXRoIGh0dHB4LkFzeW5jQ2xpZW50KHRpbWVvdXQ9MTApIGFzIGM6CiAgICAgICAgICAgICAg"
    "ICByID0gYXdhaXQgYy5nZXQoc2VsZi52YWx2ZXMuQlJPV1NFUl9BR0VOVF9VUkwgKyAiL2ZpbGVz"
    "IiwgaGVhZGVycz1zZWxmLl9oZWFkZXJzKCkpCiAgICAgICAgICAgICAgICBmaWxlcyA9IHIuanNv"
    "bigpLmdldCgiZmlsZXMiLCBbXSkKICAgICAgICAgICAgICAgIGlmIG5vdCBmaWxlczogcmV0dXJu"
    "ICLwn5OBIO2MjOydvCDsl4bsnYwgKH4vYWktc2hhcmXsl5Ag7YyM7J287J2EIOuEo+yWtOyjvOyE"
    "uOyalCkiCiAgICAgICAgICAgICAgICBsaW5lcyA9IFsi8J+TgSDtjIzsnbwg66qp66GdOiJdCiAg"
    "ICAgICAgICAgICAgICBmb3IgZiBpbiBmaWxlczoKICAgICAgICAgICAgICAgICAgICBsaW5lcy5h"
    "cHBlbmQoIiAg4oCiICIgKyBmWyJuYW1lIl0gKyAiICgiICsgc3RyKHJvdW5kKGZbInNpemUiXS8x"
    "MDI0LCAxKSkgKyAiS0IpIikKICAgICAgICAgICAgICAgIHJldHVybiAiXG4iLmpvaW4obGluZXMp"
    "CiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOiByZXR1cm4gIuyhsO2ajCDsi6TtjKg6ICIg"
    "KyBzdHIoZSkKCiAgICBhc3luYyBkZWYgcmVhZF9maWxlKHNlbGYsIGZpbGVuYW1lLCBfX2V2ZW50"
    "X2VtaXR0ZXJfXz1Ob25lKToKICAgICAgICAiIiLroZzsu6wg7YyM7J28IOydveq4sC4KICAgICAg"
    "ICA6cGFyYW0gZmlsZW5hbWU6IO2MjOydvOuqhQogICAgICAgICIiIgogICAgICAgIGlmIG5vdCBz"
    "ZWxmLnZhbHZlcy5FTkFCTEVfRklMRV9BQ0NFU1M6IHJldHVybiAi7YyM7J28IOygkeq3vCDruYTt"
    "mZzshLHtmZQiCiAgICAgICAgdHJ5OgogICAgICAgICAgICBpbXBvcnQgaHR0cHgKICAgICAgICAg"
    "ICAgYXN5bmMgd2l0aCBodHRweC5Bc3luY0NsaWVudCh0aW1lb3V0PTMwKSBhcyBjOgogICAgICAg"
    "ICAgICAgICAgciA9IGF3YWl0IGMuZ2V0KHNlbGYudmFsdmVzLkJST1dTRVJfQUdFTlRfVVJMICsg"
    "Ii9maWxlcy8iICsgZmlsZW5hbWUsIGhlYWRlcnM9c2VsZi5faGVhZGVycygpKQogICAgICAgICAg"
    "ICAgICAgaWYgci5zdGF0dXNfY29kZSA9PSA0MDQ6IHJldHVybiAi4p2MIO2MjOydvCDsl4bsnYw6"
    "ICIgKyBmaWxlbmFtZQogICAgICAgICAgICAgICAgcmV0dXJuICLwn5OEICIgKyBmaWxlbmFtZSAr"
    "ICI6XG4iICsgci5qc29uKCkuZ2V0KCJjb250ZW50IiwgIiIpWzo1MDAwXQogICAgICAgIGV4Y2Vw"
    "dCBFeGNlcHRpb24gYXMgZTogcmV0dXJuICLsnb3quLAg7Iuk7YyoOiAiICsgc3RyKGUpCgogICAg"
    "YXN5bmMgZGVmIHNhdmVfZmlsZShzZWxmLCBmaWxlbmFtZSwgY29udGVudCwgX19ldmVudF9lbWl0"
    "dGVyX189Tm9uZSk6CiAgICAgICAgIiIi66Gc7LusIO2MjOydvCDsoIDsnqUuCiAgICAgICAgOnBh"
    "cmFtIGZpbGVuYW1lOiDtjIzsnbzrqoUKICAgICAgICA6cGFyYW0gY29udGVudDog7KCA7J6l7ZWg"
    "IOuCtOyaqQogICAgICAgICIiIgogICAgICAgIGlmIG5vdCBzZWxmLnZhbHZlcy5FTkFCTEVfRklM"
    "RV9BQ0NFU1M6IHJldHVybiAi7YyM7J28IOygkeq3vCDruYTtmZzshLHtmZQiCiAgICAgICAgdHJ5"
    "OgogICAgICAgICAgICBpbXBvcnQgaHR0cHgKICAgICAgICAgICAgYXN5bmMgd2l0aCBodHRweC5B"
    "c3luY0NsaWVudCh0aW1lb3V0PTMwKSBhcyBjOgogICAgICAgICAgICAgICAgciA9IGF3YWl0IGMu"
    "cG9zdChzZWxmLnZhbHZlcy5CUk9XU0VSX0FHRU5UX1VSTCArICIvZmlsZXMvIiArIGZpbGVuYW1l"
    "LCBqc29uPXsiY29udGVudCI6Y29udGVudH0sIGhlYWRlcnM9c2VsZi5faGVhZGVycygpKQogICAg"
    "ICAgICAgICAgICAgZCA9IHIuanNvbigpCiAgICAgICAgICAgICAgICBpZiBkLmdldCgic3VjY2Vz"
    "cyIpOiByZXR1cm4gIuKchSDsoIDsnqU6ICIgKyBmaWxlbmFtZSArICIgKCIgKyBzdHIoZC5nZXQo"
    "InNpemUiLDApKSArICJCKSIKICAgICAgICAgICAgICAgIHJldHVybiAi4p2MIOyLpO2MqDogIiAr"
    "IHN0cihkKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZTogcmV0dXJuICLsoIDsnqUg7Iuk"
    "7YyoOiAiICsgc3RyKGUpCgogICAgYXN5bmMgZGVmIGNvbXBhcmVfc2l0ZXMoc2VsZiwgdGFzaywg"
    "dXJscz0iIiwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIi7Jes65+sIOyCrOyd"
    "tO2KuCDruYTqtZAg67aE7ISdICjsnKDro4wgQVBJIOq2jOyepSkuCiAgICAgICAgOnBhcmFtIHRh"
    "c2s6IOu5hOq1kCDrgrTsmqkKICAgICAgICA6cGFyYW0gdXJsczogVVJM65OkIOyJvO2RnCDqtazr"
    "toQgKOu5hOybjOuRkOuptCDsnpDrj5kpCiAgICAgICAgIiIiCiAgICAgICAgaWYgbm90IHNlbGYu"
    "dmFsdmVzLkVOQUJMRV9NVUxUSVRBQjogcmV0dXJuICLrqYDti7Dtg60g67mE7Zmc7ISx7ZmUIgog"
    "ICAgICAgIGlmIF9fZXZlbnRfZW1pdHRlcl9fOiBhd2FpdCBfX2V2ZW50X2VtaXR0ZXJfXyh7InR5"
    "cGUiOiJzdGF0dXMiLCJkYXRhIjp7ImRlc2NyaXB0aW9uIjoi66mA7Yuw7YOtIOu5hOq1kCDsi5zs"
    "npEuLi4iLCJkb25lIjpGYWxzZX19KQogICAgICAgIHVybF9saXN0ID0gW3Uuc3RyaXAoKSBmb3Ig"
    "dSBpbiB1cmxzLnNwbGl0KCIsIikgaWYgdS5zdHJpcCgpXVs6c2VsZi52YWx2ZXMuTUFYX1RBQlNd"
    "IGlmIHVybHMgZWxzZSBbXQogICAgICAgIHRyeToKICAgICAgICAgICAgaW1wb3J0IGh0dHB4CiAg"
    "ICAgICAgICAgIGJvZHkgPSB7InRhc2siOnRhc2ssInVybHMiOnVybF9saXN0LCJtYXhfc3RlcHNf"
    "cGVyX3RhYiI6OH0KICAgICAgICAgICAgaWYgc2VsZi52YWx2ZXMuTExNX1BST1ZJREVSOiBib2R5"
    "WyJwcm92aWRlciJdID0gc2VsZi52YWx2ZXMuTExNX1BST1ZJREVSCiAgICAgICAgICAgIGlmIHNl"
    "bGYudmFsdmVzLkxMTV9BUElfS0VZOiBib2R5WyJhcGlfa2V5Il0gPSBzZWxmLnZhbHZlcy5MTE1f"
    "QVBJX0tFWQogICAgICAgICAgICBpZiBzZWxmLnZhbHZlcy5MTE1fTU9ERUw6IGJvZHlbIm1vZGVs"
    "Il0gPSBzZWxmLnZhbHZlcy5MTE1fTU9ERUwKICAgICAgICAgICAgYXN5bmMgd2l0aCBodHRweC5B"
    "c3luY0NsaWVudCh0aW1lb3V0PXNlbGYudmFsdmVzLlJFUVVFU1RfVElNRU9VVCkgYXMgYzoKICAg"
    "ICAgICAgICAgICAgIHIgPSBhd2FpdCBjLnBvc3Qoc2VsZi52YWx2ZXMuQlJPV1NFUl9BR0VOVF9V"
    "UkwgKyAiL2Jyb3dzZS9tdWx0aXRhYiIsIGpzb249Ym9keSwgaGVhZGVycz1zZWxmLl9oZWFkZXJz"
    "KCkpCiAgICAgICAgICAgICAgICBkYXRhID0gci5qc29uKCkKICAgICAgICAgICAgaWYgX19ldmVu"
    "dF9lbWl0dGVyX186IGF3YWl0IF9fZXZlbnRfZW1pdHRlcl9fKHsidHlwZSI6InN0YXR1cyIsImRh"
    "dGEiOnsiZGVzY3JpcHRpb24iOiLsmYTro4wiLCJkb25lIjpUcnVlfX0pCiAgICAgICAgICAgIGlm"
    "IGRhdGEuZ2V0KCJzdWNjZXNzIik6CiAgICAgICAgICAgICAgICB0YWJzID0gZGF0YS5nZXQoInRh"
    "YnMiLFtdKQogICAgICAgICAgICAgICAgc291cmNlcyA9ICJcbiIuam9pbihbIiAg4oCiIO2DrSIg"
    "KyBzdHIodFsidGFiIl0pICsgIjogIiArIHRbInVybCJdIGZvciB0IGluIHRhYnNdKQogICAgICAg"
    "ICAgICAgICAgcmV0dXJuIGRhdGEuZ2V0KCJzdW1tYXJ5IiwiIikgKyAiXG5cbvCfk5Eg7LC47KGw"
    "OlxuIiArIHNvdXJjZXMKICAgICAgICAgICAgcmV0dXJuICLsi6TtjKg6ICIgKyBkYXRhLmdldCgi"
    "ZXJyb3IiLCIiKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgaWYg"
    "X19ldmVudF9lbWl0dGVyX186IGF3YWl0IF9fZXZlbnRfZW1pdHRlcl9fKHsidHlwZSI6InN0YXR1"
    "cyIsImRhdGEiOnsiZGVzY3JpcHRpb24iOiLsi6TtjKgiLCJkb25lIjpUcnVlfX0pCiAgICAgICAg"
    "ICAgIHJldHVybiAi66mA7Yuw7YOtIOyYpOulmDogIiArIHN0cihlKQo="
)
dest = os.environ.get('AGENT_DIR','') + '/openwebui_tool.py'
with open(dest, 'w', encoding='utf-8') as f:
    f.write(base64.b64decode(b64).decode('utf-8'))
print('  ✅ openwebui_tool.py 생성 완료')
WRITE_TOOL
ok "FILE 5/6  openwebui_tool.py"

# ── FILE 6: seccomp 프로파일 (FIX-05) ────────────────────────────────
cat > "${AGENT_DIR}/seccomp-browser.json" << 'SECCOMPEOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": [
        "accept", "accept4", "access", "arch_prctl", "bind", "brk",
        "capget", "capset", "chdir", "chmod", "chown", "clock_getres",
        "clock_gettime", "clock_nanosleep", "clone", "clone3", "close",
        "connect", "copy_file_range", "creat", "close_range",
        "dup", "dup2", "dup3",
        "epoll_create", "epoll_create1", "epoll_ctl", "epoll_pwait",
        "epoll_wait", "eventfd", "eventfd2", "execve", "execveat",
        "exit", "exit_group", "faccessat", "faccessat2",
        "fadvise64", "fallocate",
        "fchdir", "fchmod", "fchmodat", "fchown", "fchownat",
        "fcntl", "fdatasync", "fgetxattr", "flistxattr",
        "flock", "fork", "fsetxattr", "fstat", "fstatfs", "fsync",
        "ftruncate", "futex", "getcpu", "getcwd", "getdents", "getdents64",
        "getegid", "geteuid", "getgid", "getgroups", "getitimer",
        "getpeername", "getpgid", "getpgrp", "getpid", "getppid",
        "getpriority", "getrandom", "getresgid", "getresuid",
        "getrlimit", "getsid", "getsockname", "getsockopt",
        "gettid", "gettimeofday", "getuid", "getxattr",
        "inotify_add_watch", "inotify_init", "inotify_init1", "inotify_rm_watch",
        "io_cancel", "io_destroy", "io_getevents", "io_setup", "io_submit",
        "ioctl", "ipc", "kill", "lchown", "lgetxattr", "link", "linkat",
        "listen", "listxattr", "llistxattr", "lseek", "lstat",
        "madvise", "memfd_create", "mkdir", "mkdirat", "mmap", "mmap2",
        "mprotect", "mremap", "msgctl", "msgget", "msgrcv", "msgsnd",
        "munmap", "nanosleep", "newfstatat", "open", "openat", "openat2",
        "pause", "perf_event_open", "personality", "pipe", "pipe2", "poll",
        "ppoll", "prctl", "pread64", "preadv", "prlimit64",
        "process_vm_readv", "process_vm_writev", "pselect6", "ptrace",
        "pwrite64", "pwritev", "read", "readahead", "readdir",
        "readlink", "readlinkat", "readv", "recv", "recvfrom",
        "recvmmsg", "recvmsg", "rename", "renameat", "renameat2",
        "restart_syscall", "rmdir", "rt_sigaction", "rt_sigpending",
        "rt_sigprocmask", "rt_sigqueueinfo", "rt_sigreturn",
        "rt_sigsuspend", "rt_sigtimedwait", "sched_get_priority_max",
        "sched_get_priority_min", "sched_getaffinity", "sched_getattr",
        "sched_getparam", "sched_getscheduler", "sched_setaffinity",
        "sched_setattr", "sched_setparam", "sched_setscheduler",
        "sched_yield", "select", "semctl", "semget", "semop",
        "send", "sendfile", "sendmmsg", "sendmsg", "sendto",
        "set_robust_list", "set_tid_address", "setfsgid", "setfsuid",
        "setgid", "setgroups", "setitimer", "setpgid", "setpriority",
        "setregid", "setresgid", "setresuid", "setreuid", "setsid",
        "setsockopt", "setuid", "setxattr", "shmat", "shmctl",
        "shmdt", "shmget", "shutdown", "sigaltstack", "signal",
        "signalfd", "signalfd4", "sigprocmask", "sigreturn",
        "socket", "socketcall", "socketpair", "splice", "stat",
        "statfs", "statx", "symlink", "symlinkat", "sync",
        "sync_file_range", "sysinfo", "tgkill", "time", "timerfd_create",
        "timerfd_gettime", "timerfd_settime", "times", "tkill",
        "truncate", "umask", "uname", "unlink", "unlinkat",
        "userfaultfd", "utime", "utimensat", "utimes", "vfork",
        "wait4", "waitid", "waitpid", "write", "writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
SECCOMPEOF
chmod 644 "${AGENT_DIR}/seccomp-browser.json"
ok "FILE 6/6  seccomp-browser.json"

# ── FILE 7: logrotate 설정 (FIX-09) ──────────────────────────────────
cat > "${AGENT_DIR}/logrotate.conf" << 'LOGROTATEOF'
/app/data/audit/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    maxsize 10M
}
LOGROTATEOF
ok "logrotate.conf 생성"


# ── Phase 2 스텁 파일들 ───────────────────────────────────────────────
# tools-api Dockerfile
[ -f "${TOOLS_API_DIR}/Dockerfile" ] || cat > "${TOOLS_API_DIR}/Dockerfile" << 'TDOCKEREOF'
FROM python:3.12-slim-bookworm
ENV DEBIAN_FRONTEND=noninteractive
RUN pip install --no-cache-dir fastapi==0.136.1 uvicorn==0.46.0 \
    python-multipart==0.0.20 pydantic==2.12.5 PyMuPDF==1.25.0 httpx==0.28.1
WORKDIR /app
COPY . /app
RUN useradd -u 1001 -m appuser && chown -R appuser /app
USER appuser
EXPOSE 8010
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8010"]
TDOCKEREOF

# tools-api requirements.txt
[ -f "${TOOLS_API_DIR}/requirements.txt" ] || cat > "${TOOLS_API_DIR}/requirements.txt" << 'TFREQEOF'
fastapi==0.136.1
uvicorn==0.46.0
python-multipart==0.0.20
pydantic==2.12.5
PyMuPDF==1.25.0
httpx==0.28.1
python-dotenv==1.2.1
TFREQEOF

# tools-api main.py 스텁 (없을 경우만)
[ -f "${TOOLS_API_DIR}/main.py" ] || cat > "${TOOLS_API_DIR}/main.py" << 'TMAINEOF'
"""
Tools API — Phase 2
PDF 업로드 및 OpenWebUI 연동 도구 서버
start-openwebui-with-rag-groq-ollama-Twilio-final.sh 로 생성되는 파일과 통합 사용
"""
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
import os, shutil

app = FastAPI(title="Tools API", version="1.0.0")
DATA_DIR = "/app/data"
os.makedirs(DATA_DIR, exist_ok=True)

@app.get("/health")
def health():
    return {"status": "ok", "service": "tools-api"}

@app.post("/upload/pdf")
async def upload_pdf(file: UploadFile = File(...)):
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(400, "PDF 파일만 허용됩니다.")
    dest = os.path.join(DATA_DIR, file.filename)
    with open(dest, "wb") as f:
        shutil.copyfileobj(file.file, f)
    return JSONResponse({"status": "ok", "filename": file.filename})

@app.get("/files")
def list_files():
    files = os.listdir(DATA_DIR)
    return {"files": files}
TMAINEOF
ok "Phase 2 tools-api 스텁 파일 생성"

# twilio-bot Dockerfile 스텁
[ -f "${TWILIO_BOT_DIR}/Dockerfile" ] || cat > "${TWILIO_BOT_DIR}/Dockerfile" << 'WBDOCKEREOF'
FROM python:3.12-slim-bookworm
ENV DEBIAN_FRONTEND=noninteractive
RUN pip install --no-cache-dir \
    twilio==9.2.3 flask==3.0.0 \
    fpdf2==2.7.9 requests==2.31.0 \
    apscheduler==3.10.4 python-dotenv==1.2.1
WORKDIR /app
COPY . /app
RUN useradd -u 1001 -m appuser && chown -R appuser /app
USER appuser
EXPOSE 8020
CMD ["python", "twilio_bot.py"]
WBDOCKEREOF

# twilio-bot requirements.txt
[ -f "${TWILIO_BOT_DIR}/requirements.txt" ] || cat > "${TWILIO_BOT_DIR}/requirements.txt" << 'WBREQEOF'
twilio==9.2.3
flask==3.0.0
fpdf2==2.7.9
requests==2.31.0
apscheduler==3.10.4
python-dotenv==1.2.1
WBREQEOF
ok "Phase 2 twilio-bot 스텁 파일 생성"

# Phase 3 telegram bridge 스텁
[ -f "${TELEGRAM_DIR}/bot/Dockerfile" ] || cat > "${TELEGRAM_DIR}/bot/Dockerfile" << 'TGDOCKEREOF'
FROM python:3.12-slim-bookworm
ENV DEBIAN_FRONTEND=noninteractive
RUN pip install --no-cache-dir \
    python-telegram-bot==22.7 \
    httpx==0.28.1 python-dotenv==1.2.1
WORKDIR /app
COPY . /app
RUN useradd -u 1001 -m appuser && chown -R appuser /app
USER appuser
CMD ["python", "telegram_bot.py"]
TGDOCKEREOF

[ -f "${TELEGRAM_DIR}/bot/requirements.txt" ] || cat > "${TELEGRAM_DIR}/bot/requirements.txt" << 'TGREQEOF'
python-telegram-bot==22.7
httpx==0.28.1
python-dotenv==1.2.1
TGREQEOF

# Phase 3 docker-compose.yml 스텁
[ -f "${TELEGRAM_DIR}/docker-compose.yml" ] || cat > "${TELEGRAM_DIR}/docker-compose.yml" << TGCOMPOSEEOF
services:
  telegram-bot:
    build: ./bot
    container_name: telegram-openwebui-bot
    restart: unless-stopped
    environment:
      - TELEGRAM_BOT_TOKEN=\${TELEGRAM_BOT_TOKEN}
      - OPENWEBUI_URL=${OWUI_HOST}
      - OPENWEBUI_API_KEY=\${OPENWEBUI_API_KEY}
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp:size=64M
    deploy:
      resources:
        limits:
          memory: 256M
    healthcheck:
      test: ["CMD","python3","-c","print('ok')"]
      interval: 60s
      timeout: 10s
      retries: 3
TGCOMPOSEEOF

# Phase 3 .env 스텁 (없을 경우만)
if [ ! -f "${TELEGRAM_DIR}/.env" ]; then
    cat > "${TELEGRAM_DIR}/.env" << TGENVEOF
TELEGRAM_BOT_TOKEN=your_telegram_bot_token_here
OPENWEBUI_API_KEY=${OWUI_API_KEY}
OPENWEBUI_URL=${OWUI_HOST}
TGENVEOF
    chmod 600 "${TELEGRAM_DIR}/.env"
fi
# ai-share 디렉토리 생성 (로컬 파일 공유용)
mkdir -p "${HOME}/ai-share"
ok "~/ai-share 디렉토리 생성 (로컬 파일 공유용)"

ok "Phase 3 telegram-openwebui-bridge 스텁 파일 생성"

# ══════════════════════════════════════════════════════════════════════
# SECTION 4 — docker-compose.yml 업데이트
# ══════════════════════════════════════════════════════════════════════
step "5/9  docker-compose.yml 업데이트"
cd "$OWUI_DIR"

# 백업 생성 후 오래된 백업 정리
cp "$COMPOSE_FILE" "${COMPOSE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
_cleanup_bak "$OWUI_DIR" "docker-compose.yml.bak.*"

if grep -q "browser-agent:" "$COMPOSE_FILE" 2>/dev/null; then
    warn "기존 browser-agent 블록 교체 중..."
    export COMPOSE_FILE
    python3 << 'PYREMOVE'
import os, re
p = os.environ["COMPOSE_FILE"]
with open(p) as f: c = f.read()
c = re.sub(r'\n  browser-agent:.*?(?=\n  \w|\nnetworks:|\nvolumes:|\Z)',
           '', c, flags=re.DOTALL)
with open(p, 'w') as f: f.write(c)
PYREMOVE
fi

if ! grep -q "^networks:" "$COMPOSE_FILE"; then
    printf '\nnetworks:\n  openwebui_net:\n    driver: bridge\n' >> "$COMPOSE_FILE"
fi

export COMPOSE_FILE SHM_SIZE BUILD_START_PERIOD CONTAINER_CPUS CONTAINER_MEMORY \
       BROWSER_API_KEY OWUI_API_KEY \
       INTERNAL_TOKEN OPENWEBUI_INTERNAL_URL LITE_MODE SCREEN_RESOLUTION \
       MAX_STEPS_AGENT HAS_GPU OWUI_HOST AGENT_DIR IS_WSL

python3 << 'PYINSERT'
import re, os

p            = os.environ["COMPOSE_FILE"]
shm_size     = os.environ.get("SHM_SIZE",              "512mb")
start_period = os.environ.get("BUILD_START_PERIOD",    "45s")
cpus         = os.environ.get("CONTAINER_CPUS",        "1.5")
memory       = os.environ.get("CONTAINER_MEMORY",      "2G")
# [v6] SLOW_MO removed (VNC only)
llm_provider = os.environ.get("LLM_PROVIDER",           "")
openai_key   = os.environ.get("OPENAI_API_KEY",         "")
anthropic_key= os.environ.get("ANTHROPIC_API_KEY",       "")
google_key   = os.environ.get("GOOGLE_API_KEY",          "")
# [v6] VNC removed
groq_model   = os.environ.get("GROQ_MODEL",           "llama-3.3-70b-versatile")
browser_key  = os.environ.get("BROWSER_API_KEY",       "")
owui_key     = os.environ.get("OWUI_API_KEY",          "")
int_token    = os.environ.get("INTERNAL_TOKEN",        "")
owui_int_url = os.environ.get("OPENWEBUI_INTERNAL_URL","http://openwebui:8080")
lite_mode    = os.environ.get("LITE_MODE",             "false")
screen_res   = os.environ.get("SCREEN_RESOLUTION",     "1280x800x24")
max_steps    = os.environ.get("MAX_STEPS_AGENT",       "10")
has_gpu      = os.environ.get("HAS_GPU",               "false")
owui_host    = os.environ.get("OWUI_HOST",             "")
agent_dir    = os.environ.get("AGENT_DIR",             "")
is_wsl       = os.environ.get("IS_WSL",                "false")

gpu_runtime = "    runtime: nvidia\n" if has_gpu == "true" else ""

# [FIX-05] WSL2: privileged 모드 사용 (runc openat2 미지원 우회)
#          네이티브: 커스텀 seccomp 프로파일 사용
if is_wsl == "true":
    security_block = """    privileged: true
    security_opt:
      - no-new-privileges:true"""
else:
    seccomp_profile = os.path.join(agent_dir, "seccomp-browser.json")
    if os.path.exists(seccomp_profile):
        seccomp_line = f"      - seccomp:{seccomp_profile}"
    else:
        seccomp_line = "      - seccomp:unconfined"
    security_block = f"""    security_opt:
      - no-new-privileges:true
{seccomp_line}"""

with open(p) as f: c = f.read()

block = f"""
  browser-agent:
    build: ./browser-agent
    container_name: browser-agent
    restart: unless-stopped
    ports:
      # [FIX-24] VNC 포트 로컬 전용 (외부 접근 차단)
      - "127.0.0.1:8001:8001"
    environment:
      - USE_VISION=false
      - GROQ_MODEL={groq_model}
      - BROWSER_AGENT_API_KEY={browser_key}
      - BROWSER_INTERNAL_TOKEN={int_token}
      - OPENWEBUI_API_KEY={owui_key}
      - OPENWEBUI_URL={owui_int_url}
      - WEBUI_URL={owui_host}
      - TZ=Asia/Seoul
      - LITE_MODE={lite_mode}
      - MAX_STEPS_AGENT={max_steps}
      - LLM_PROVIDER={llm_provider}
      - OPENAI_API_KEY={openai_key}
      - ANTHROPIC_API_KEY={anthropic_key}
      - GOOGLE_API_KEY={google_key}
      - TASK_TIMEOUT=180
      - MULTI_TIMEOUT=300
      - MAX_CONCURRENT=3
      - GROQ_API_KEY=${{GROQ_API_KEY:-}}
    volumes:
      - ./browser-agent/data:/app/data
      - ./browser-agent/secrets:/app/secrets:ro
      - ./browser-agent/data:/app/data
      - ~/ai-share:/app/data/user_files
      - ./browser-agent/logrotate.conf:/etc/logrotate.d/browser-agent:ro
    read_only: true
    networks:
      - default
      - openwebui_net
    user: "1001:1001"
    shm_size: '{shm_size}'
    cap_drop:
      - ALL
    cap_add:
      - SYS_ADMIN
      - NET_BIND_SERVICE
      - SETUID
      - SETGID
    deploy:
      resources:
        limits:
          cpus: "{cpus}"
          memory: {memory}
        reservations:
          memory: 512M
{gpu_runtime}{security_block}
    tmpfs:
      - /tmp:size=200M,mode=1777
      - /home/appuser/.config:size=64M,uid=1001,gid=1001
    healthcheck:
      test: ["CMD","python3","-c",
             "import urllib.request; urllib.request.urlopen('http://localhost:8001/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: {start_period}
"""

pat = r'(\nnetworks:|\nvolumes:)'
if re.search(pat, c):
    c = re.sub(pat, block + r'\1', c, count=1)
else:
    c += block

with open(p, 'w') as f: f.write(c)
PYINSERT
ok "docker-compose.yml 업데이트 완료"

# ══════════════════════════════════════════════════════════════════════
# SECTION 5 — Docker 이미지 빌드
# ══════════════════════════════════════════════════════════════════════
step "6/9  Docker 이미지 빌드"
docker compose build browser-agent
ok "빌드 완료"

# ══════════════════════════════════════════════════════════════════════
# SECTION 6 — 서비스 시작
# ══════════════════════════════════════════════════════════════════════
step "7/9  서비스 시작"

MAX_START_WAIT=120
MAX_RETRIES=3
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
    RETRY=$((RETRY+1))
    info "컨테이너 시작 시도 ($RETRY/$MAX_RETRIES)..."
    docker compose up -d browser-agent 2>&1 || true
    sleep 5   # 컨테이너 초기화 대기

    # 컨테이너 실행 상태 확인
    if docker compose ps browser-agent 2>/dev/null | grep -qE "running|Up"; then
        ok "컨테이너 시작됨"
        break
    fi

    warn "컨테이너가 즉시 종료됨 — 로그 확인:"
    docker compose logs --tail=15 browser-agent 2>/dev/null || true

    if [ $RETRY -lt $MAX_RETRIES ]; then
        info "10초 후 재시도..."
        docker compose rm -f browser-agent 2>/dev/null || true
        sleep 10
    else
        err "컨테이너 시작 실패 ($MAX_RETRIES회 시도) — 로그를 확인하세요."
    fi
done

info "초기화 대기 중 (Browser Use + FastAPI)... 최대 ${MAX_START_WAIT}초"

COUNT=0
until docker compose exec -T browser-agent \
    python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/health')" \
    &>/dev/null; do
    COUNT=$((COUNT+1))

    # 컨테이너가 도중에 죽었는지 확인
    if ! docker compose ps browser-agent 2>/dev/null | grep -qE "running|Up"; then
        warn "컨테이너가 중간에 종료됨 — 재시작 시도..."
        docker compose up -d browser-agent 2>&1 || true
        sleep 5
    fi

    [ $COUNT -ge $MAX_START_WAIT ] && {
        docker compose logs --tail=30 browser-agent
        err "서버 응답 없음 (${MAX_START_WAIT}초 초과) — 로그 확인 후 재시도하세요"
    }
    printf "."; sleep 1
done
echo ""
ok "서버 실행 중"

# ══════════════════════════════════════════════════════════════════════
# SECTION 7 — OpenWebUI 도구 자동 등록
# ══════════════════════════════════════════════════════════════════════
step "8/9  OpenWebUI 도구 자동 등록"

# [FIX-20] API 키 플레이스홀더를 실제 값으로 치환
cp "${AGENT_DIR}/openwebui_tool.py" "$TOOL_TMP"
sed -i "s|__BROWSER_API_KEY_PLACEHOLDER__|${BROWSER_API_KEY}|g" "$TOOL_TMP"
chmod 600 "$TOOL_TMP"

# [FIX-02] ADMIN_PASS를 환경변수로 전달 (CLI 인자 ps 노출 방지)
export _OWUI_REGISTER_PASS="$ADMIN_PASS"
export OWUI_HOST ADMIN_EMAIL TOOL_TMP
python3 << 'PYEOF'
import json, sys, os, urllib.request, urllib.error, signal, time

base      = os.environ["OWUI_HOST"].rstrip("/")
email     = os.environ["ADMIN_EMAIL"]
tool_file = os.environ["TOOL_TMP"]
password  = os.environ.pop("_OWUI_REGISTER_PASS", "")

def _timeout(sig, frame):
    print("\n⏰ 도구 등록 시간 초과"); sys.exit(1)
signal.signal(signal.SIGALRM, _timeout)
signal.alarm(60)
print(f"  🔧 '{email}' 계정으로 도구 등록 중...")

def req(url, p=None, t=None, m="POST"):
    d = json.dumps(p).encode() if p else None
    h = {"Content-Type": "application/json"}
    if t: h["Authorization"] = f"Bearer {t}"
    r = urllib.request.Request(url, data=d, headers=h, method=m)
    try:
        with urllib.request.urlopen(r, timeout=15) as resp:
            body = resp.read()
            try: return resp.status, json.loads(body) if body else {}
            except Exception: return resp.status, {}
    except urllib.error.HTTPError as e:
        body = e.read() or b""
        try: return e.code, json.loads(body) if body else {}
        except Exception: return e.code, {}
    except Exception: return 0, {}

def try_signin(url, email, pw):
    return req(f"{url}/api/v1/auths/signin", {"email": email, "password": pw})

s, b = try_signin(base, email, password)
if s != 200:
    print(f"  ⚠️  {base} 연결 실패(HTTP {s}) -> localhost:3000 으로 재시도...")
    base = "http://localhost:3000"
    s, b = try_signin(base, email, password)
signal.alarm(0)

if s != 200:
    print(f"ERR:로그인 실패(HTTP {s}) - 이메일/비밀번호를 확인하세요.")
    sys.exit(1)

token = b.get("token","")
if not token:
    print("ERR:토큰 없음"); sys.exit(1)


s, ex = req(f"{base}/api/v1/tools/", t=token, m="GET")
ids = [x.get("id","") for x in (ex if isinstance(ex, list) else [])]

TOOL_ID = "ai_browser_agent"
with open(tool_file) as f: tool_content = f.read()

tool_payload = {
    "id": TOOL_ID,
    "name": "AI 브라우저 에이전트",
    "content": tool_content,
    "meta": {
        "description": "AI 브라우저 에이전트: browse_web으로 웹 작업, search_web으로 검색, check_weather로 날씨 확인. Browser Use + Groq 기반."
    }
}

# [FIX-21] 기존 도구가 있으면 update, 없으면 create
if TOOL_ID in ids:
    print(f"  🔄  기존 도구 '{TOOL_ID}' 업데이트 중...")
    s, b = req(f"{base}/api/v1/tools/id/{TOOL_ID}/update", t=token, p=tool_payload)
    if s in (200, 201):
        print("  ✅ 도구 업데이트 성공")
    else:
        # 업데이트 실패 시 삭제 후 재생성 시도
        print(f"  ⚠️  업데이트 실패(HTTP {s}), 삭제 후 재생성 시도...")
        h = {"Content-Type": "application/json", "Authorization": f"Bearer {token}"}
        r = urllib.request.Request(
            f"{base}/api/v1/tools/id/{TOOL_ID}", headers=h, method="DELETE")
        try:
            with urllib.request.urlopen(r, timeout=10) as resp: ds = resp.status
        except urllib.error.HTTPError as e: ds = e.code
        except Exception: ds = 0
        if ds in (200,204):
            print("  ✅ 삭제 완료 → 재생성 중...")
        s, b = req(f"{base}/api/v1/tools/create", t=token, p=tool_payload)
        if s in (200, 201):
            print("  ✅ 도구 재생성 성공")
        else:
            print(f"  ❌ 도구 등록 실패 (HTTP {s})\n{json.dumps(b, indent=2, ensure_ascii=False)}")
            sys.exit(1)
else:
    print(f"  ✨ 새 도구 '{TOOL_ID}' 등록 중...")
    s, b = req(f"{base}/api/v1/tools/create", t=token, p=tool_payload)
    if s in (200, 201):
        print("  ✅ 도구 등록 성공")
    else:
        print(f"  ❌ 도구 등록 실패 (HTTP {s})\n{json.dumps(b, indent=2, ensure_ascii=False)}")
        sys.exit(1)
PYEOF
unset _OWUI_REGISTER_PASS
# [FIX-39] 토큰 삭제를 MCP Hub 등록 후로 이동 (기존: 여기서 삭제해서 MCP Hub 등록 실패)

ok "OpenWebUI 브라우저 에이전트 도구 등록 완료"

rm -f /tmp/.owui_token  # 보안: 임시 토큰 삭제

ok "OpenWebUI 도구 등록 완료"

# ══════════════════════════════════════════════════════════════════════
# SECTION 8 — 종합 동작 검증 (NEW)
# ══════════════════════════════════════════════════════════════════════
step "9/9  종합 동작 검증"

VERIFY_OK=true

# ── 8-1. 컨테이너 상태 확인 ──────────────────────────────────────────
info "8-1. 컨테이너 상태 확인..."
CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' browser-agent 2>/dev/null || echo "missing")
CONTAINER_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' browser-agent 2>/dev/null || echo "none")

if [ "$CONTAINER_STATUS" = "running" ]; then
    ok "컨테이너 상태: running"
else
    warn "컨테이너 상태: ${CONTAINER_STATUS}"
    VERIFY_OK=false
fi

if [ "$CONTAINER_HEALTH" = "healthy" ] || [ "$CONTAINER_HEALTH" = "none" ]; then
    ok "컨테이너 헬스: ${CONTAINER_HEALTH}"
elif [ "$CONTAINER_HEALTH" = "starting" ]; then
    info "헬스체크 아직 시작 중 (starting) — 정상"
else
    warn "컨테이너 헬스: ${CONTAINER_HEALTH}"
    VERIFY_OK=false
fi

# ── 8-2. HTTP /health 엔드포인트 확인 ────────────────────────────────
info "8-2. API 헬스 엔드포인트 확인..."
HEALTH_RESP=$(docker compose exec -T browser-agent \
    python3 -c "
import urllib.request, json
try:
    with urllib.request.urlopen('http://localhost:8001/health', timeout=5) as r:
        print(json.dumps({'status': r.status, 'body': json.loads(r.read())}))
except Exception as e:
    print(json.dumps({'status': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"status":0}')

HTTP_STATUS=$(echo "$HEALTH_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',0))" 2>/dev/null || echo "0")
if [ "$HTTP_STATUS" = "200" ]; then
    ok "API /health 응답: HTTP 200"
    # 버전 확인
    API_VER=$(echo "$HEALTH_RESP" | python3 -c "
import json,sys
b = json.load(sys.stdin).get('body',{})
print(b.get('version','unknown'))
" 2>/dev/null || echo "unknown")
    info "API 버전: ${API_VER}"
else
    warn "API /health 응답 실패 (HTTP ${HTTP_STATUS})"
    VERIFY_OK=false
fi

# ── 8-3. API 키 인증 테스트 ────────────────────────────────────────────
info "8-3. API 키 인증 테스트..."
AUTH_TEST=$(docker compose exec -T browser-agent \
    python3 -c "
import urllib.request, json
req = urllib.request.Request(
    'http://localhost:8001/vnc-token',
    data=b'{}',
    headers={'Authorization': 'Bearer WRONG_KEY', 'Content-Type': 'application/json'},
    method='POST')
try:
    with urllib.request.urlopen(req, timeout=5) as r: print(r.status)
except urllib.error.HTTPError as e: print(e.code)
except Exception: print(0)
" 2>/dev/null || echo "0")

if [ "$AUTH_TEST" = "403" ] || [ "$AUTH_TEST" = "401" ]; then
    ok "잘못된 API 키 거부 확인 (HTTP ${AUTH_TEST}) ✔"
else
    warn "인증 거부 테스트 실패 (응답: ${AUTH_TEST})"
    VERIFY_OK=false
fi

# ── 8-4. Browser Use 엔진 확인 ──────────────────────────────────────
info "8-4. Browser Use 엔진 확인..."
BU_CHECK=$(docker compose exec -T browser-agent \
    python3 -c "import browser_use; print('OK')" 2>/dev/null || echo "FAIL")
if [ "$BU_CHECK" = "OK" ]; then
    ok "Browser Use 엔진 로드 성공"
else
    warn "Browser Use 엔진 로드 실패"
    VERIFY_OK=false
fi

# ── 8-5. Playwright Chromium 확인 ──────────────────────────────────
info "8-5. Playwright Chromium 확인..."
PW_CHECK=$(docker compose exec -T browser-agent \
    python3 -c "from playwright.sync_api import sync_playwright; print('OK')" 2>/dev/null || echo "FAIL")
if [ "$PW_CHECK" = "OK" ]; then
    ok "Playwright Chromium 사용 가능"
else
    warn "Playwright Chromium 확인 실패"
fi
API_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 3 "http://localhost:8001/health" 2>/dev/null || echo "000")
if [ "$API_CHECK" = "200" ] || [ "$API_CHECK" = "301" ] || [ "$API_CHECK" = "302" ]; then
    ok "Browser Agent API 응답: HTTP ${API_CHECK}"
else
    warn "Browser Agent API 응답 없음 — 컨테이너 로그 확인 필요"
fi

# ── 8-6. Docker 네트워크 연결 확인 ─────────────────────────────────────
info "8-6. Docker 네트워크 확인 (openwebui_net + openwebui_default)..."
NET_CHECK=$(docker network inspect openwebui_net --format \
    '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
if echo "$NET_CHECK" | grep -q "browser-agent"; then
    ok "browser-agent → openwebui_net 연결됨"
else
    # [FIX-27] openwebui_default에 연결되어 있으면 정상 (경고 아님)
    info "browser-agent가 openwebui_net에 없음 (openwebui_default로 통신 — 정상)"
fi
# [FIX] openwebui_default 네트워크도 확인 (open-webui와 통신용)
NET_DEFAULT=$(docker network inspect openwebui_default --format \
    '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
if echo "$NET_DEFAULT" | grep -q "browser-agent"; then
    ok "browser-agent → openwebui_default 연결됨 (open-webui 통신 가능)"
else
    warn "browser-agent가 openwebui_default에 없음 — open-webui 통신 불가"
    VERIFY_OK=false
fi

# ── 8-7. OpenWebUI 연결 가능성 확인 ─────────────────────────────────
info "8-7. OpenWebUI 연결 확인 (${OWUI_HOST})..."
OWUI_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 --max-time 10 "${OWUI_HOST}/" 2>/dev/null || echo "000")
if [ "$OWUI_CHECK" = "200" ] || [ "$OWUI_CHECK" = "302" ] || [ "$OWUI_CHECK" = "301" ]; then
    ok "OpenWebUI 응답 확인: HTTP ${OWUI_CHECK}"
else
    warn "OpenWebUI 응답 없음 (HTTP ${OWUI_CHECK}) — 서비스 실행 여부 확인"
fi

# ── 8-8. .env 파일 권한 확인 ──────────────────────────────────────────
# [FIX-25] 방화벽 권장 안내

# ── 8-7.5. Multi-Agent 상태 확인 ────────────────────────────────────
info "8-7.5. Multi-Agent 모듈 확인..."
MULTI_HEALTH=$(docker compose exec -T browser-agent \
    python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8001/health/multi').read().decode())" 2>/dev/null || echo "")
if echo "$MULTI_HEALTH" | grep -q "true"; then
    ok "Multi-Agent 모듈 활성화 확인"
else
    if [ -n "$GROQ_API_KEY" ]; then
        warn "Multi-Agent 모듈 로드 실패 — docker logs browser-agent 확인"
    else
        info "Multi-Agent 비활성 (GROQ_API_KEY 미설정)"
    fi
fi

info "8-8. 방화벽(UFW) 상태 확인..."
UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1 || echo "")
if echo "$UFW_STATUS" | grep -qi "active"; then
    ok "UFW 방화벽 활성화됨"
else
    warn "UFW 방화벽이 비활성화 상태입니다"
    info "클라우드 서버 배포 시 아래 명령어로 방화벽을 활성화하세요:"
    info "  sudo ufw allow ssh && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw enable"
fi

info "8-9. .env 파일 권한 확인..."
ENV_PERM=$(stat -c "%a" "$ENV_FILE" 2>/dev/null || echo "000")
if [ "$ENV_PERM" = "600" ]; then
    ok ".env 권한: 600 (소유자만 읽기/쓰기)"
else
    warn ".env 권한: ${ENV_PERM} (600이 아님 — 보안 위험)"
    chmod 600 "$ENV_FILE"
    ok ".env 권한 600으로 수정 완료"
fi

# ── 8-9. secrets 디렉토리 권한 확인 ─────────────────────────────────
info "8-10. secrets 디렉토리 권한 확인..."
if [ -d "$SECRETS_DIR" ]; then
    SEC_PERM=$(stat -c "%a" "$SECRETS_DIR" 2>/dev/null || echo "000")
    if [ "$SEC_PERM" = "700" ] || [ "$SEC_PERM" = "750" ]; then
        ok "secrets 디렉토리 권한: ${SEC_PERM}"
    else
        warn "secrets 권한: ${SEC_PERM} — 700으로 수정"
        # [FIX-28] 컨테이너 사용자(uid 1001) 소유이므로 sudo 필요
        sudo chmod 700 "$SECRETS_DIR" 2>/dev/null || {
            info "sudo 권한 없음 — 수동 실행 필요: sudo chmod 700 $SECRETS_DIR"
        }
    fi
fi

# ── 8-11. 디렉토리 구조 최종 확인 ────────────────────────────────────
info "8-11. 디렉토리 구조 확인..."
for CHECK_DIR in \
    "${OWUI_DIR}" \
    "${AGENT_DIR}" \
    "${TOOLS_API_DIR}" \
    "${TWILIO_BOT_DIR}" \
    "${TWILIO_BOT_DIR}/data/recordings" \
    "${TWILIO_BOT_DIR}/data/reports" \
    "${TELEGRAM_DIR}" \
    "${TELEGRAM_DIR}/bot" \
    "${TELEGRAM_DIR}/data" \
    "${TELEGRAM_DIR}/logs"; do
    if [ -d "$CHECK_DIR" ]; then
        ok "  ✔ ${CHECK_DIR}"
    else
        warn "  ✗ 누락: ${CHECK_DIR}"
        VERIFY_OK=false
    fi
done

# ── 최종 결과 ─────────────────────────────────────────────────────────
echo ""
if [ "$VERIFY_OK" = "true" ]; then
    echo -e "${G}${B}╔═══════════════════════════════════════════════════╗${N}"
    echo -e "${G}${B}║  🎉  모든 검증 통과! 설치가 완료되었습니다.       ║${N}"
    echo -e "${G}${B}╚═══════════════════════════════════════════════════╝${N}"
else
    echo -e "${Y}${B}╔═══════════════════════════════════════════════════╗${N}"
    echo -e "${Y}${B}║  ⚠️  일부 검증 경고 있음 — 위 내용을 확인하세요.   ║${N}"
    echo -e "${Y}${B}╚═══════════════════════════════════════════════════╝${N}"
fi

echo ""
info "── 접속 정보 ────────────────────────────────────────────────"
info "  OpenWebUI:    ${OWUI_HOST}"
info "  Browser API:  http://localhost:8001/health (Browser Use Agent)"
info "  tools-api:    ${OWUI_HOST%/*}:8010/health  (Phase 2)"
info "  twilio-bot:   ${OWUI_HOST%/*}:8020/health  (Phase 2)"
info "  Telegram:     ${TELEGRAM_DIR}/.env 에 BOT TOKEN 입력 후 실행"
info "─────────────────────────────────────────────────────────────"
info "  Phase 2 시작: cd ~/OpenWebUI && docker compose up -d tools-api twilio-bot"
info "  Phase 3 시작: cd ~/telegram-openwebui-bridge && docker compose up -d"
info "  전체 로그:    docker compose logs -f browser-agent"
info "  Multi-Agent: POST http://localhost:8001/browse/multi (Browser Use+Groq)"
info "  ※ Multi-Agent는 비교/추천/분석/계획 등 복잡한 작업에 사용"
info "  보안 감사:    cat ${AGENT_DIR}/data/audit/agent.log"
