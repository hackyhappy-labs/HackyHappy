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
    echo "   bash setup-browser-agent-browser-use-v7.sh"
    exit 1
}

# 민감 정보 입력 (확인 단계 포함):
#   1) 입력 (타이핑은 화면에 숨김)
#   2) 마스킹(****) + 글자 수 표시로 입력 확인
#   3) Y/Enter=확정, n=재입력, s=실제값 확인 후 재확인
# 입력값은 stdout으로만 반환되며, 모든 안내는 stderr(>&2)로 출력됩니다.
# 사용법: VAR=$(read_secret "프롬프트: " [timeout] [on_timeout])
#   - timeout: 입력 대기 초 (기본 $INPUT_TIMEOUT)
#   - on_timeout: "exit"(기본)=timeout_exit 호출 / "skip"=빈 문자열 반환(선택 입력용)
#   - 빈 입력은 빈 문자열을 그대로 반환(이후 검증/건너뜀 로직에 위임)
read_secret() {
    local prompt="$1"
    local timeout="${2:-$INPUT_TIMEOUT}"
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
# (Twilio 봇은 별도 스크립트 start-twilio-bot.sh 가 ~/TwilioBot 에 독립 설치)

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

# 관리자 비밀번호 입력 (숨김 + 확인 단계)
if [ -z "$ADMIN_PASS" ]; then
    echo -e "${Y}OpenWebUI 관리자 비밀번호 (${INPUT_TIMEOUT}초 내 입력):${N}"
    ADMIN_PASS=$(read_secret "  🔒 비밀번호: ")
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
        OWUI_API_KEY=$(read_secret "  🔑 API Key: ")
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
    "GROQ_MODEL=${GROQ_MODEL:-qwen/qwen3.8-27b}" \
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
    GROQ_API_KEY=$(read_secret "  Groq API Key (Enter=건너뜀): " 120 skip)
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

# ══════════════════════════════════════════════════════════════════════
# [NAVER-SEARCH-ONLY] 네이버 검색 API 키 입력
# ══════════════════════════════════════════════════════════════════════
step "검색 API 키 설정 (네이버 Search API 전용)"
info "검색은 네이버 공식 Search API만 사용합니다."
info "  • Endpoint: https://naverapihub.apigw.ntruss.com/search/v1/webkr"
info "  • 인증: X-NCP-APIGW-API-KEY-ID + X-NCP-APIGW-API-KEY"
info "  • 다른 검색 API는 사용하지 않습니다."

EXISTING_NAVER_ID="$(_env NAVER_CLIENT_ID)"
EXISTING_NAVER_SECRET="$(_env NAVER_CLIENT_SECRET)"

if [ -n "$EXISTING_NAVER_ID" ] && [ -n "$EXISTING_NAVER_SECRET" ]; then
    NAVER_CLIENT_ID="$EXISTING_NAVER_ID"
    NAVER_CLIENT_SECRET="$EXISTING_NAVER_SECRET"
    ok "기존 NAVER Search API 인증정보 감지 ($(masked "$NAVER_CLIENT_ID")) — 재사용"
else
    echo -e "${Y}네이버 Search API Client ID를 입력하세요:${N}"
    NAVER_CLIENT_ID=$(read_secret "  🟢 NAVER Client ID: " 120 skip)
    [ -n "$NAVER_CLIENT_ID" ] || err "NAVER Client ID가 필요합니다."

    echo -e "${Y}네이버 Search API Client Secret을 입력하세요:${N}"
    NAVER_CLIENT_SECRET=$(read_secret "  🟢 NAVER Client Secret: " 120 skip)
    [ -n "$NAVER_CLIENT_SECRET" ] || err "NAVER Client Secret이 필요합니다."
fi

# 실제 네이버 Search API를 호출해 키/구독 상태를 설치 단계에서 검증합니다.
# 실패한 키를 .env에 저장한 뒤 나중에 Docker에서 조용히 실패하는 것을 방지합니다.
while true; do
    echo -e "${C}  🔎 네이버 Search API 인증 및 검색 권한을 실제 요청으로 확인합니다...${N}"
    _NAVER_TEST_CODE=$(curl -sS --get --connect-timeout 5 --max-time 15 \
        -o /tmp/.naver_search_test.json -w "%{http_code}" \
        -H "X-NCP-APIGW-API-KEY-ID: ${NAVER_CLIENT_ID}" \
        -H "X-NCP-APIGW-API-KEY: ${NAVER_CLIENT_SECRET}" \
        --data-urlencode "query=네이버" \
        --data-urlencode "display=1" \
        --data-urlencode "format=json" \
        "https://naverapihub.apigw.ntruss.com/search/v1/webkr" 2>/dev/null || echo "000")

    if [ "$_NAVER_TEST_CODE" = "200" ]; then
        ok "네이버 Search API 인증/검색 테스트 성공"
        rm -f /tmp/.naver_search_test.json
        break
    fi

    _NAVER_TEST_MSG=$(python3 - <<'PYERR'
import json
try:
    with open('/tmp/.naver_search_test.json', encoding='utf-8') as f:
        d=json.load(f)
    print(d.get('errorMessage') or d.get('message') or '')
except Exception:
    print('')
PYERR
)
    rm -f /tmp/.naver_search_test.json

    case "$_NAVER_TEST_CODE" in
        401) warn "네이버 API HUB 인증 실패 (HTTP 401). NAVER API HUB에서 발급한 Client ID/Secret과 헤더 권한을 확인하세요." ;;
        403) warn "네이버 API HUB 접근 거부 (HTTP 403). NAVER API HUB 애플리케이션에 Search API 권한이 등록되어 있는지 확인하세요." ;;
        429) warn "네이버 호출 한도 초과 (HTTP 429). 잠시 후 다시 시도하세요." ;;
        000) warn "네이버 API 접속 실패. 서버의 HTTPS/DNS/방화벽을 확인하세요." ;;
        *)   warn "네이버 Search API 테스트 실패 (HTTP ${_NAVER_TEST_CODE}) ${_NAVER_TEST_MSG}" ;;
    esac
    echo -e "${Y}키를 다시 입력하시겠습니까? (Y=재입력 / N=중단):${N}"
    read -t 30 -r _NAVER_RETRY || timeout_exit
    [[ "$_NAVER_RETRY" =~ ^[Yy]$ ]] || err "네이버 API HUB 인증/권한 검증 실패로 설치를 중단합니다."
    NAVER_CLIENT_ID=$(read_secret "  🟢 NAVER Client ID: " 120 skip)
    [ -n "$NAVER_CLIENT_ID" ] || err "NAVER Client ID가 필요합니다."
    NAVER_CLIENT_SECRET=$(read_secret "  🟢 NAVER Client Secret: " 120 skip)
    [ -n "$NAVER_CLIENT_SECRET" ] || err "NAVER Client Secret이 필요합니다."
done

_set_env() {
    local k="$1" v="$2"
    [ -z "$v" ] && return 0
    if grep -q "^${k}=" "$ENV_FILE" 2>/dev/null; then
        python3 - "$k" "$v" "$ENV_FILE" << 'PYSET'
import sys
k, v, p = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(p, encoding="utf-8").read().splitlines()
out = []
for ln in lines:
    if ln.startswith(k + "="):
        out.append("%s=%s" % (k, v))
    else:
        out.append(ln)
open(p, "w", encoding="utf-8").write("\n".join(out) + "\n")
PYSET
    else
        echo "${k}=${v}" >> "$ENV_FILE"
    fi
}
_set_env NAVER_CLIENT_ID "$NAVER_CLIENT_ID"
_set_env NAVER_CLIENT_SECRET "$NAVER_CLIENT_SECRET"
# 기존 .env의 다른 사용자 정의 설정은 건드리지 않습니다.
chmod 600 "$ENV_FILE" 2>/dev/null || true
ok "NAVER_CLIENT_ID / NAVER_CLIENT_SECRET → .env 저장 완료"

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

# 참고: Twilio 봇은 별도 스크립트(start-twilio-bot.sh)가 ~/TwilioBot 에 독립 설치합니다.
#       이 스크립트는 ~/OpenWebUI/twilio-bot 스텁을 만들지 않습니다.

# ── Phase 3: telegram-openwebui-bridge ───────────────────────────────
mkdir -p "${TELEGRAM_DIR}/bot" \
         "${TELEGRAM_DIR}/data" \
         "${TELEGRAM_DIR}/logs"
chmod 750 "${TELEGRAM_DIR}"
# ai-share 디렉토리 생성 (로컬 파일 공유용)
mkdir -p "${HOME}/ai-share"
# 🔒 메인 스크립트와 동일한 공유 권한(setgid+그룹쓰기) 적용 — uid 1001/1002 공유 충돌 방지
chmod 2775 "${HOME}/ai-share" 2>/dev/null || chmod 775 "${HOME}/ai-share" 2>/dev/null || true
ok "~/ai-share 디렉토리 생성 (로컬 파일 공유용)"

ok "Phase 3 telegram-openwebui-bridge 디렉토리 생성"

ok "전체 디렉토리 구조 생성 완료"
info "구조:"
info "  ~/OpenWebUI/browser-agent/  (Phase 1)"
info "  ~/OpenWebUI/tools-api/      (Phase 2)"
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
    PYTHONUNBUFFERED=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

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
    playwright==1.52.0 \
    sse-starlette==1.6.5 \
    openpyxl==3.1.5 \
    httpx==0.28.1

WORKDIR /app
COPY --chown=appuser:appuser . /app
RUN mkdir -p /app/multi_agent
RUN chmod +x /app/entrypoint.sh \
    && mkdir -p /app/data /app/secrets \
    && chown -R appuser:appuser /app/data /app/secrets

# [FIX] Chromium을 root 단계에서 고정 경로(/ms-playwright)에 설치
#       → read_only 런타임 + appuser(uid 1001) 환경에서도 항상 발견 가능
RUN playwright install --with-deps chromium \
    && chmod -R a+rX /ms-playwright

USER appuser
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
echo "Model: ${GROQ_MODEL:-qwen/qwen3.8-27b}"
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
    "X1RJTUVPVVQiLCAiMzAwIikpICAgICAjIE11bHRpLUFnZW50IOy1nOuMgCAzMDDstIgKTVVMVElf"
    "QlVER0VUX1VTRCA9IGZsb2F0KG9zLmdldGVudigiTVVMVElfQlVER0VUX1VTRCIsICIwIikpICAj"
    "IE11bHRpLUFnZW50IOq4sOuzuCDruYTsmqkg7IOB7ZWcICgwPeustOygnO2VnCkKU1RFUF9USU1F"
    "T1VUID0gaW50KG9zLmdldGVudigiU1RFUF9USU1FT1VUIiwgIjMwIikpICAgICAgICAjIOuLqOyd"
    "vCDsiqTthZ0g7LWc64yAIDMw7LSICgojIOKUgOKUgCBbdjddIOuEpOydtOuyhCBTZWFyY2ggQVBJ"
    "IOyghOyaqSDtgqQg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSACk5BVkVSX0NMSUVOVF9JRCAgICAgPSBvcy5nZXRlbnYoIk5B"
    "VkVSX0NMSUVOVF9JRCIsICIiKQpOQVZFUl9DTElFTlRfU0VDUkVUID0gb3MuZ2V0ZW52KCJOQVZF"
    "Ul9DTElFTlRfU0VDUkVUIiwgIiIpClNFQVJDSF9USU1FT1VUICAgICAgPSBpbnQob3MuZ2V0ZW52"
    "KCJTRUFSQ0hfVElNRU9VVCIsICIxNSIpKQpTRUFSQ0hfQ0FDSEVfVFRMICAgID0gaW50KG9zLmdl"
    "dGVudigiU0VBUkNIX0NBQ0hFX1RUTCIsICIzMDAiKSkKX3NlYXJjaF9jYWNoZSA9IHt9CgojIFtT"
    "RUNVUklUWV0g7ZeI7JqpIOuPhOuplOyduCAo67mI6rCSID0g7KCE7LK0IO2XiOyaqSkKQUxMT1dF"
    "RF9PUklHSU5TID0gb3MuZ2V0ZW52KCJBTExPV0VEX09SSUdJTlMiLCAiIikuc3BsaXQoIiwiKQpB"
    "TExPV0VEX09SSUdJTlMgPSBbby5zdHJpcCgpIGZvciBvIGluIEFMTE9XRURfT1JJR0lOUyBpZiBv"
    "LnN0cmlwKCldCgojIFtTRUNVUklUWV0g7LCo64uoIFVSTCDtjKjthLQKQkxPQ0tFRF9VUkxfUEFU"
    "VEVSTlMgPSBbCiAgICByIl5maWxlOi8vIiwgciJeamF2YXNjcmlwdDoiLCByIl5kYXRhOiIsCiAg"
    "ICByIl5mdHA6Ly8iLCByIl5jaHJvbWU6Ly8iLCByIl5hYm91dDoiLAogICAgciJsb2NhbGhvc3Q6"
    "XGQrL2FkbWluIiwgciIxMjdcLjBcLjBcLjEiLAogICAgciIxNjlcLjI1NFwuIiwgciIxMFwuXGQr"
    "XC5cZCtcLlxkKyIsICAjIOuCtOu2gCDrhKTtirjsm4ztgawKICAgIHIiMTkyXC4xNjhcLiIsIHIi"
    "MTcyXC4oMVs2LTldfDJcZHwzWzAxXSlcLiIsCl0KCiMg4pSA4pSAIFJhdGUgTGltaXRlciDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKbGltaXRlciA9IExpbWl0ZXIoa2V5X2Z1bmM9"
    "Z2V0X3JlbW90ZV9hZGRyZXNzKQoKIyDilIDilIAgTExNIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApsbG0gPSBOb25lCgpkZWYgX2xv"
    "YWRfYXBpX2tleSgpOgogICAgaWYgQVBJX0tFWTogcmV0dXJuIEFQSV9LRVkKICAgIHRyeToKICAg"
    "ICAgICBwID0gUGF0aCgiL2FwcC9zZWNyZXRzL2FwaV9rZXkiKQogICAgICAgIGlmIHAuZXhpc3Rz"
    "KCk6IHJldHVybiBwLnJlYWRfdGV4dCgpLnN0cmlwKCkKICAgIGV4Y2VwdCBFeGNlcHRpb246IHBh"
    "c3MKICAgIHJldHVybiAiIgoKIyBbU0VDVVJJVFldIOyDgeyImCDsi5zqsIQg67mE6rWQ66GcIO2D"
    "gOydtOuwjSDqs7Xqsqkg67Cp7KeACmRlZiB2ZXJpZnlfYXBpX2tleShyZXF1ZXN0OiBSZXF1ZXN0"
    "KToKICAgIGF1dGggPSByZXF1ZXN0LmhlYWRlcnMuZ2V0KCJBdXRob3JpemF0aW9uIiwgIiIpCiAg"
    "ICBrZXkgPSBfbG9hZF9hcGlfa2V5KCkKICAgIGlmIG5vdCBrZXk6IHJldHVybiBUcnVlCiAgICB0"
    "b2tlbiA9IGF1dGgucmVwbGFjZSgiQmVhcmVyICIsICIiKS5zdHJpcCgpCiAgICBpZiBub3QgdG9r"
    "ZW46CiAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJBVVRIX01JU1NJTkd8e3JlcXVlc3QuY2xp"
    "ZW50Lmhvc3R9fHtyZXF1ZXN0LnVybC5wYXRofSIpCiAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlv"
    "bihzdGF0dXNfY29kZT00MDEsIGRldGFpbD0iQXV0aG9yaXphdGlvbiByZXF1aXJlZCIpCiAgICBp"
    "ZiBub3QgaG1hYy5jb21wYXJlX2RpZ2VzdCh0b2tlbi5lbmNvZGUoKSwga2V5LmVuY29kZSgpKToK"
    "ICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIkFVVEhfRkFJTHx7cmVxdWVzdC5jbGllbnQuaG9z"
    "dH18e3JlcXVlc3QudXJsLnBhdGh9IikKICAgICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKHN0YXR1"
    "c19jb2RlPTQwMywgZGV0YWlsPSJJbnZhbGlkIEFQSSBrZXkiKQogICAgcmV0dXJuIFRydWUKCiMg"
    "W1NFQ1VSSVRZXSBVUkwg6rKA7KadCmRlZiB2YWxpZGF0ZV91cmwodXJsOiBzdHIpIC0+IGJvb2w6"
    "CiAgICBpZiBub3QgdXJsOiByZXR1cm4gVHJ1ZQogICAgdHJ5OgogICAgICAgIHBhcnNlZCA9IHVy"
    "bHBhcnNlKHVybCkKICAgICAgICBpZiBwYXJzZWQuc2NoZW1lIG5vdCBpbiAoImh0dHAiLCAiaHR0"
    "cHMiLCAiIik6CiAgICAgICAgICAgIHJldHVybiBGYWxzZQogICAgICAgIGZvciBwYXR0ZXJuIGlu"
    "IEJMT0NLRURfVVJMX1BBVFRFUk5TOgogICAgICAgICAgICBpZiBfcmUuc2VhcmNoKHBhdHRlcm4s"
    "IHVybCwgX3JlLklHTk9SRUNBU0UpOgogICAgICAgICAgICAgICAgcmV0dXJuIEZhbHNlCiAgICAg"
    "ICAgcmV0dXJuIFRydWUKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuIEZhbHNl"
    "CgojIFtTRUNVUklUWV0g7J6F66ClIOyDiOuLiO2DgOydtOynlQpkZWYgc2FuaXRpemVfdGFzayh0"
    "YXNrOiBzdHIpIC0+IHN0cjoKICAgICMg7KCc7Ja0IOusuOyekCDsoJzqsbAKICAgIHRhc2sgPSAi"
    "Ii5qb2luKGMgZm9yIGMgaW4gdGFzayBpZiBjLmlzcHJpbnRhYmxlKCkgb3IgYyBpbiAiXG5cdCIp"
    "CiAgICAjIO2UhOuhrO2UhO2KuCDsnbjsoJ3shZgg7Yyo7YS0IOqyveqzoAogICAgaW5qZWN0aW9u"
    "X3BhdHRlcm5zID0gWwogICAgICAgICJpZ25vcmUgcHJldmlvdXMiLCAiaWdub3JlIGFib3ZlIiwg"
    "ImRpc3JlZ2FyZCIsCiAgICAgICAgInN5c3RlbSBwcm9tcHQiLCAieW91IGFyZSBub3ciLCAibmV3"
    "IGluc3RydWN0aW9ucyIsCiAgICAgICAgImZvcmdldCBldmVyeXRoaW5nIiwgIm92ZXJyaWRlIiwg"
    "ImphaWxicmVhayIsCiAgICBdCiAgICB0YXNrX2xvd2VyID0gdGFzay5sb3dlcigpCiAgICBmb3Ig"
    "cCBpbiBpbmplY3Rpb25fcGF0dGVybnM6CiAgICAgICAgaWYgcCBpbiB0YXNrX2xvd2VyOgogICAg"
    "ICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIklOSkVDVElPTl9BVFRFTVBUfHtwfXx7dGFza1s6"
    "MTAwXX0iKQogICAgICAgICAgICBicmVhawogICAgcmV0dXJuIHRhc2suc3RyaXAoKQoKCiMgW05B"
    "VkVSLVBSSU9SSVRZXSDtlZzqta3slrQg6rCQ7KeAICsg64Sk7J2067KEIOyasOyEoCDqsoDsg4kg"
    "66Gc7KeBCktPUkVBTl9TRUFSQ0hfUEFUVEVSTlMgPSB7CiAgICAi64Kg7JSoIjogImh0dHBzOi8v"
    "c2VhcmNoLm5hdmVyLmNvbS9zZWFyY2gubmF2ZXI/cXVlcnk9e3F9K+uCoOyUqCIsCiAgICAi7KO8"
    "6rCAIjogImh0dHBzOi8vc2VhcmNoLm5hdmVyLmNvbS9zZWFyY2gubmF2ZXI/cXVlcnk9e3F9K+yj"
    "vOqwgCIsCiAgICAi7ZmY7JyoIjogImh0dHBzOi8vc2VhcmNoLm5hdmVyLmNvbS9zZWFyY2gubmF2"
    "ZXI/cXVlcnk9e3F9K+2ZmOycqCIsCiAgICAi64m07IqkIjogImh0dHBzOi8vbmV3cy5uYXZlci5j"
    "b20iLAogICAgIuqwgOqyqSI6ICJodHRwczovL3NlYXJjaC5uYXZlci5jb20vc2VhcmNoLm5hdmVy"
    "P3F1ZXJ5PXtxfSvqsIDqsqkiLAp9CgpkZWYgZGV0ZWN0X2tvcmVhbih0ZXh0OiBzdHIpIC0+IGJv"
    "b2w6CiAgICAiIiLtlZzqta3slrQg7Y+s7ZWoIOyXrOu2gCDqsJDsp4AiIiIKICAgIHJldHVybiBh"
    "bnkoMHhBQzAwIDw9IG9yZChjKSA8PSAweEQ3QTMgb3IgMHgzMTMxIDw9IG9yZChjKSA8PSAweDMx"
    "OEUgZm9yIGMgaW4gdGV4dCkKCmRlZiBhcHBseV9uYXZlcl9wcmlvcml0eSh0YXNrOiBzdHIpIC0+"
    "IHN0cjoKICAgICIiIu2VnOq1reyWtCDsnpHsl4Xsl5Ag64Sk7J2067KEIOyasOyEoCDqsoDsg4kg"
    "7KeA7IucIOy2lOqwgCIiIgogICAgaWYgbm90IGRldGVjdF9rb3JlYW4odGFzayk6CiAgICAgICAg"
    "cmV0dXJuIHRhc2sKICAgIAogICAgIyDsnbTrr7ggVVJM7J20IO2PrO2VqOuQnCDqsr3smrAg6rG0"
    "65Oc66as7KeAIOyViuydjAogICAgaWYgImh0dHA6Ly8iIGluIHRhc2sgb3IgImh0dHBzOi8vIiBp"
    "biB0YXNrOgogICAgICAgIHJldHVybiB0YXNrCiAgICAKICAgICMg7Yq57KCVIO2CpOybjOuTnCDr"
    "p6Tsua0g4oaSIOuEpOydtOuyhCBVUkwg7J6Q64+ZIOyCveyehQogICAgdGFza19sb3dlciA9IHRh"
    "c2subG93ZXIoKQogICAgZm9yIGtleXdvcmQsIHVybF90ZW1wbGF0ZSBpbiBLT1JFQU5fU0VBUkNI"
    "X1BBVFRFUk5TLml0ZW1zKCk6CiAgICAgICAgaWYga2V5d29yZCBpbiB0YXNrOgogICAgICAgICAg"
    "ICAjIO2CpOybjOuTnCDslZ7rkqQg7Luo7YWN7Iqk7Yq4IOy2lOy2nCAo7JiIOiAi7ISc7Jq4IOuC"
    "oOyUqCIg4oaSIHE9IuyEnOyauCIpCiAgICAgICAgICAgIGltcG9ydCB1cmxsaWIucGFyc2UKICAg"
    "ICAgICAgICAgcSA9IHRhc2sucmVwbGFjZShrZXl3b3JkLCAiIikucmVwbGFjZSgi7JWM66Ck7KSY"
    "IiwiIikucmVwbGFjZSgi7ZmV7J24IiwiIikucmVwbGFjZSgi6rKA7IOJIiwiIikuc3RyaXAoKQog"
    "ICAgICAgICAgICBpZiBub3QgcTogcSA9IHRhc2sucmVwbGFjZShrZXl3b3JkLCIiKS5zdHJpcCgp"
    "IG9yIGtleXdvcmQKICAgICAgICAgICAgdXJsID0gdXJsX3RlbXBsYXRlLmZvcm1hdChxPXVybGxp"
    "Yi5wYXJzZS5xdW90ZShxKSkKICAgICAgICAgICAgcmV0dXJuIGYiR28gdG8ge3VybH0gYW5kIHt0"
    "YXNrfS4gUmVzcG9uZCBpbiBLb3JlYW4uIgogICAgCiAgICAjIOydvOuwmCDtlZzqta3slrQg7L+8"
    "66asIOKGkiDrhKTsnbTrsoQg6rKA7IOJIOyasOyEoAogICAgcmV0dXJuIGYiVXNlIHRoZSBOYXZl"
    "ciBTZWFyY2ggQVBJIG9ubHkgZm9yOiB7dGFza30uIERvIG5vdCB1c2UgR29vZ2xlLCBCaW5nLCBU"
    "YXZpbHksIG9yIGFueSBvdGhlciBzZWFyY2ggc2VydmljZS4gQWx3YXlzIHJlc3BvbmQgaW4gS29y"
    "ZWFuLiIKCiMgW1NFQ1VSSVRZXSDrj5nsi5wg7Iuk7ZaJIOygnO2VnApfYWN0aXZlX3Rhc2tzID0g"
    "MApfYWN0aXZlX2xvY2sgPSBhc3luY2lvLkxvY2soKQpNQVhfQ09OQ1VSUkVOVCA9IGludChvcy5n"
    "ZXRlbnYoIk1BWF9DT05DVVJSRU5UIiwgIjMiKSkKCkBhc3luY2NvbnRleHRtYW5hZ2VyCmFzeW5j"
    "IGRlZiB0YXNrX3Nsb3QoKToKICAgIGdsb2JhbCBfYWN0aXZlX3Rhc2tzCiAgICBhc3luYyB3aXRo"
    "IF9hY3RpdmVfbG9jazoKICAgICAgICBpZiBfYWN0aXZlX3Rhc2tzID49IE1BWF9DT05DVVJSRU5U"
    "OgogICAgICAgICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKDQyOSwgZiJUb28gbWFueSBjb25jdXJy"
    "ZW50IHRhc2tzICh7TUFYX0NPTkNVUlJFTlR9IG1heCkiKQogICAgICAgIF9hY3RpdmVfdGFza3Mg"
    "Kz0gMQogICAgdHJ5OgogICAgICAgIHlpZWxkCiAgICBmaW5hbGx5OgogICAgICAgIGFzeW5jIHdp"
    "dGggX2FjdGl2ZV9sb2NrOgogICAgICAgICAgICBfYWN0aXZlX3Rhc2tzIC09IDEKCkBhc3luY2Nv"
    "bnRleHRtYW5hZ2VyCmFzeW5jIGRlZiBsaWZlc3BhbihhcHA6IEZhc3RBUEkpOgogICAgZ2xvYmFs"
    "IGxsbQogICAgIyDrqYDti7Ag7ZSE66Gc67CU7J20642UIOyekOuPmSDqsJDsp4AKICAgIHRyeToK"
    "ICAgICAgICBsbG0gPSBjcmVhdGVfbGxtKHByb3ZpZGVyPUxMTV9QUk9WSURFUikKICAgICAgICBs"
    "b2dnZXIuaW5mbyhmIkxMTSBpbml0OiBwcm92aWRlcj17bGxtLnByb3ZpZGVyfSwgbW9kZWw9e2dl"
    "dGF0dHIobGxtLCAnbW9kZWxfbmFtZScsIGdldGF0dHIobGxtLCAnbW9kZWwnLCAndW5rbm93bicp"
    "KX0iKQogICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgIGxvZ2dlci5lcnJvcihmIkxM"
    "TSBpbml0IGZhaWxlZDoge2V9IikKICAgICAgICBsb2dnZXIuZXJyb3IoIlNldCBhdCBsZWFzdCBv"
    "bmUgQVBJIGtleTogR1JPUV9BUElfS0VZLCBPUEVOQUlfQVBJX0tFWSwgQU5USFJPUElDX0FQSV9L"
    "RVksIG9yIEdPT0dMRV9BUElfS0VZIikKICAgIGxvZ2dlci5pbmZvKGYiVGltZW91dHM6IHRhc2s9"
    "e1RBU0tfVElNRU9VVH1zIG11bHRpPXtNVUxUSV9USU1FT1VUfXMgc3RlcD17U1RFUF9USU1FT1VU"
    "fXMiKQogICAgbG9nZ2VyLmluZm8oZiJDb25jdXJyZW5jeSBsaW1pdDoge01BWF9DT05DVVJSRU5U"
    "fSIpCiAgICB5aWVsZAoKYXBwID0gRmFzdEFQSSh0aXRsZT0iQnJvd3NlciBVc2UgQWdlbnQiLCB2"
    "ZXJzaW9uPSI2LjIuMCIsIGxpZmVzcGFuPWxpZmVzcGFuLAogICAgICAgICAgICAgIGRvY3NfdXJs"
    "PU5vbmUsIHJlZG9jX3VybD1Ob25lKSAgIyBbU0VDVVJJVFldIFN3YWdnZXIgVUkg67mE7Zmc7ISx"
    "7ZmUCmFwcC5zdGF0ZS5saW1pdGVyID0gbGltaXRlcgoKQGFwcC5leGNlcHRpb25faGFuZGxlcihS"
    "YXRlTGltaXRFeGNlZWRlZCkKYXN5bmMgZGVmIHJhdGVfbGltaXRfaGFuZGxlcihyZXF1ZXN0LCBl"
    "eGMpOgogICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJSQVRFX0xJTUlUfHtyZXF1ZXN0LmNsaWVudC5o"
    "b3N0fXx7cmVxdWVzdC51cmwucGF0aH0iKQogICAgcmV0dXJuIEpTT05SZXNwb25zZShzdGF0dXNf"
    "Y29kZT00MjksIGNvbnRlbnQ9eyJlcnJvciI6ICJSYXRlIGxpbWl0IGV4Y2VlZGVkIn0pCgojIFtT"
    "RUNVUklUWV0gQ09SUyDsoJztlZwKaWYgQUxMT1dFRF9PUklHSU5TOgogICAgYXBwLmFkZF9taWRk"
    "bGV3YXJlKENPUlNNaWRkbGV3YXJlLCBhbGxvd19vcmlnaW5zPUFMTE9XRURfT1JJR0lOUywKICAg"
    "ICAgICBhbGxvd19tZXRob2RzPVsiR0VUIiwiUE9TVCJdLCBhbGxvd19oZWFkZXJzPVsiQXV0aG9y"
    "aXphdGlvbiIsIkNvbnRlbnQtVHlwZSJdKQplbHNlOgogICAgYXBwLmFkZF9taWRkbGV3YXJlKENP"
    "UlNNaWRkbGV3YXJlLCBhbGxvd19vcmlnaW5zPVsiKiJdLAogICAgICAgIGFsbG93X21ldGhvZHM9"
    "WyJHRVQiLCJQT1NUIl0sIGFsbG93X2hlYWRlcnM9WyIqIl0pCgojIFtTRUNVUklUWV0g67O07JWI"
    "IO2XpOuNlCDrr7jrk6Tsm6jslrQKQGFwcC5taWRkbGV3YXJlKCJodHRwIikKYXN5bmMgZGVmIHNl"
    "Y3VyaXR5X2hlYWRlcnMocmVxdWVzdDogUmVxdWVzdCwgY2FsbF9uZXh0KToKICAgICMgW1NFQ1VS"
    "SVRZXSDsmpTssq0g67O466y4IO2BrOq4sCDsoJztlZwgKDEwS0IpCiAgICBjb250ZW50X2xlbmd0"
    "aCA9IHJlcXVlc3QuaGVhZGVycy5nZXQoImNvbnRlbnQtbGVuZ3RoIiwgIjAiKQogICAgaWYgaW50"
    "KGNvbnRlbnRfbGVuZ3RoKSA+IDEwMjQwOgogICAgICAgIHJldHVybiBKU09OUmVzcG9uc2Uoc3Rh"
    "dHVzX2NvZGU9NDEzLCBjb250ZW50PXsiZXJyb3IiOiAiUmVxdWVzdCB0b28gbGFyZ2UifSkKICAg"
    "IHJlc3BvbnNlID0gYXdhaXQgY2FsbF9uZXh0KHJlcXVlc3QpCiAgICByZXNwb25zZS5oZWFkZXJz"
    "WyJYLUNvbnRlbnQtVHlwZS1PcHRpb25zIl0gPSAibm9zbmlmZiIKICAgIHJlc3BvbnNlLmhlYWRl"
    "cnNbIlgtRnJhbWUtT3B0aW9ucyJdID0gIkRFTlkiCiAgICByZXNwb25zZS5oZWFkZXJzWyJYLVhT"
    "Uy1Qcm90ZWN0aW9uIl0gPSAiMTsgbW9kZT1ibG9jayIKICAgIHJlc3BvbnNlLmhlYWRlcnNbIlJl"
    "ZmVycmVyLVBvbGljeSJdID0gInN0cmljdC1vcmlnaW4td2hlbi1jcm9zcy1vcmlnaW4iCiAgICBy"
    "ZXNwb25zZS5oZWFkZXJzWyJQZXJtaXNzaW9ucy1Qb2xpY3kiXSA9ICJjYW1lcmE9KCksIG1pY3Jv"
    "cGhvbmU9KCksIGdlb2xvY2F0aW9uPSgpIgogICAgcmVzcG9uc2UuaGVhZGVyc1siQ29udGVudC1T"
    "ZWN1cml0eS1Qb2xpY3kiXSA9ICJkZWZhdWx0LXNyYyAnbm9uZSc7IGZyYW1lLWFuY2VzdG9ycyAn"
    "bm9uZSciCiAgICByZXNwb25zZS5oZWFkZXJzWyJDYWNoZS1Db250cm9sIl0gPSAibm8tc3RvcmUs"
    "IG5vLWNhY2hlLCBtdXN0LXJldmFsaWRhdGUiCiAgICByZXNwb25zZS5oZWFkZXJzWyJQcmFnbWEi"
    "XSA9ICJuby1jYWNoZSIKICAgIHJlc3BvbnNlLmhlYWRlcnNbIlgtUmVxdWVzdC1JRCJdID0gc2Vj"
    "cmV0cy50b2tlbl9oZXgoOCkKICAgIHJldHVybiByZXNwb25zZQoKIyDilIDilIAg66qo6424IOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApj"
    "bGFzcyBNdWx0aVRhYlJlcXVlc3QoQmFzZU1vZGVsKToKICAgIHRhc2s6IHN0ciA9IEZpZWxkKC4u"
    "LiwgbWluX2xlbmd0aD0xLCBtYXhfbGVuZ3RoPTIwMDAsIGRlc2NyaXB0aW9uPSLruYTqtZAv67aE"
    "7ISd7ZWgIOyekeyXhSIpCiAgICB1cmxzOiBsaXN0W3N0cl0gPSBGaWVsZChkZWZhdWx0PVtdLCBt"
    "YXhfbGVuZ3RoPTUsIGRlc2NyaXB0aW9uPSLrsKnrrLjtlaAgVVJMIOuqqeuhnSAo7LWc64yAIDXq"
    "sJwpIikKICAgIG1heF9zdGVwc19wZXJfdGFiOiBpbnQgPSBGaWVsZChkZWZhdWx0PTgsIGdlPTEs"
    "IGxlPTE1KQogICAgcHJvdmlkZXI6IE9wdGlvbmFsW3N0cl0gPSBOb25lCiAgICBhcGlfa2V5OiBP"
    "cHRpb25hbFtzdHJdID0gTm9uZQogICAgbW9kZWw6IE9wdGlvbmFsW3N0cl0gPSBOb25lCgpjbGFz"
    "cyBCcm93c2VSZXF1ZXN0KEJhc2VNb2RlbCk6CiAgICB0YXNrOiBzdHIgPSBGaWVsZCguLi4sIG1p"
    "bl9sZW5ndGg9MSwgbWF4X2xlbmd0aD0yMDAwKQogICAgdXJsOiBPcHRpb25hbFtzdHJdID0gRmll"
    "bGQoTm9uZSwgbWF4X2xlbmd0aD01MDApCiAgICBtYXhfc3RlcHM6IE9wdGlvbmFsW2ludF0gPSBG"
    "aWVsZChOb25lLCBnZT0xLCBsZT0zMCkKICAgIHVzZV92aXNpb246IE9wdGlvbmFsW2Jvb2xdID0g"
    "Tm9uZQogICAgcHJvdmlkZXI6IE9wdGlvbmFsW3N0cl0gPSBGaWVsZChOb25lLCBkZXNjcmlwdGlv"
    "bj0iTExNIHByb3ZpZGVyOiBncm9xL29wZW5haS9hbnRocm9waWMvZ29vZ2xlIikKICAgIGFwaV9r"
    "ZXk6IE9wdGlvbmFsW3N0cl0gPSBGaWVsZChOb25lLCBkZXNjcmlwdGlvbj0iT3ZlcnJpZGUgQVBJ"
    "IGtleSIpCiAgICBtb2RlbDogT3B0aW9uYWxbc3RyXSA9IEZpZWxkKE5vbmUsIGRlc2NyaXB0aW9u"
    "PSJPdmVycmlkZSBtb2RlbCBuYW1lIikKICAgIGJ1ZGdldF91c2Q6IE9wdGlvbmFsW2Zsb2F0XSA9"
    "IEZpZWxkKE5vbmUsIGdlPTAsIGxlPTEwLAogICAgICAgIGRlc2NyaXB0aW9uPSJNdWx0aS1BZ2Vu"
    "dCBMTE0g67mE7JqpIOyDge2VnCAoVVNEKS4gMCDrmJDripQg66+47KeA7KCV7J2066m0IOustOyg"
    "nO2VnC4iKQoKICAgIEBmaWVsZF92YWxpZGF0b3IoInVybCIpCiAgICBAY2xhc3NtZXRob2QKICAg"
    "IGRlZiBjaGVja191cmwoY2xzLCB2KToKICAgICAgICBpZiB2IGFuZCBub3QgdmFsaWRhdGVfdXJs"
    "KHYpOgogICAgICAgICAgICByYWlzZSBWYWx1ZUVycm9yKCJVUkwgbm90IGFsbG93ZWQgKGJsb2Nr"
    "ZWQgc2NoZW1lIG9yIGludGVybmFsIG5ldHdvcmspIikKICAgICAgICByZXR1cm4gdgoKICAgIEBm"
    "aWVsZF92YWxpZGF0b3IoInRhc2siKQogICAgQGNsYXNzbWV0aG9kCiAgICBkZWYgY2hlY2tfdGFz"
    "ayhjbHMsIHYpOgogICAgICAgIHJldHVybiBzYW5pdGl6ZV90YXNrKHYpCgpjbGFzcyBCcm93c2VS"
    "ZXNwb25zZShCYXNlTW9kZWwpOgogICAgc3VjY2VzczogYm9vbAogICAgc3VtbWFyeTogT3B0aW9u"
    "YWxbc3RyXSA9IE5vbmUKICAgIHN1bW1hcnlfcGxhaW46IE9wdGlvbmFsW3N0cl0gPSBOb25lCiAg"
    "ICBlcnJvcjogT3B0aW9uYWxbc3RyXSA9IE5vbmUKICAgIHN0ZXBzX3Rha2VuOiBpbnQgPSAwCiAg"
    "ICBlbGFwc2VkX3NlYzogZmxvYXQgPSAwLjAKICAgIHRpbWVzdGFtcDogc3RyID0gIiIKCiMg4pSA"
    "4pSAIOu4jOudvOyasOyggCDsi6Ttlokg7Zes7Y28ICjtg4DsnoTslYTsm4Mg7Y+s7ZWoKSDilIDi"
    "lIDilIDilIDilIDilIDilIDilIAKYXN5bmMgZGVmIF9ydW5fYWdlbnQodGFzazogc3RyLCBzdGVw"
    "czogaW50LCB2aXNpb246IGJvb2wsIG92ZXJyaWRlX2xsbT1Ob25lKSAtPiBkaWN0OgogICAgc2Vz"
    "c2lvbiA9IE5vbmUKICAgIHQwID0gdGltZS50aW1lKCkKICAgIHRyeToKICAgICAgICBzZXNzaW9u"
    "ID0gQnJvd3NlclNlc3Npb24oYnJvd3Nlcl9wcm9maWxlPUJyb3dzZXJQcm9maWxlKAogICAgICAg"
    "ICAgICBoZWFkbGVzcz1UcnVlLCBkaXNhYmxlX3NlY3VyaXR5PUZhbHNlLAogICAgICAgICAgICB2"
    "aWV3cG9ydD17IndpZHRoIjogMTI4MCwgImhlaWdodCI6IDcyMH0pKQoKICAgICAgICBhY3RpdmVf"
    "bGxtID0gb3ZlcnJpZGVfbGxtIG9yIGxsbQogICAgICAgIGFnZW50ID0gQWdlbnQodGFzaz10YXNr"
    "LCBsbG09YWN0aXZlX2xsbSwgYnJvd3Nlcl9zZXNzaW9uPXNlc3Npb24sCiAgICAgICAgICAgICAg"
    "ICAgICAgICB1c2VfdmlzaW9uPXZpc2lvbiwgbWF4X2FjdGlvbnNfcGVyX3N0ZXA9NSkKCiAgICAg"
    "ICAgIyBbQU5USS1MT09QXSBhc3luY2lvLndhaXRfZm9y66GcIOyghOyytCDtg4DsnoTslYTsm4Mg"
    "7KCB7JqpCiAgICAgICAgcmVzdWx0ID0gYXdhaXQgYXN5bmNpby53YWl0X2ZvcigKICAgICAgICAg"
    "ICAgYWdlbnQucnVuKG1heF9zdGVwcz1zdGVwcyksCiAgICAgICAgICAgIHRpbWVvdXQ9VEFTS19U"
    "SU1FT1VUCiAgICAgICAgKQoKICAgICAgICBmaW5hbCA9IHJlc3VsdC5maW5hbF9yZXN1bHQoKSBp"
    "ZiByZXN1bHQgZWxzZSAiY29tcGxldGVkIgogICAgICAgIGhpc3RvcnkgPSByZXN1bHQuaGlzdG9y"
    "eSBpZiByZXN1bHQgZWxzZSBbXQogICAgICAgIG4gPSBsZW4oaGlzdG9yeSkgaWYgaGlzdG9yeSBl"
    "bHNlIDAKICAgICAgICBlbGFwc2VkID0gcm91bmQodGltZS50aW1lKCkgLSB0MCwgMikKCiAgICAg"
    "ICAgcmV0dXJuIHsic3VjY2VzcyI6IFRydWUsICJzdW1tYXJ5IjogZmluYWwsICJzdW1tYXJ5X3Bs"
    "YWluIjogZmluYWwsCiAgICAgICAgICAgICAgICAic3RlcHNfdGFrZW4iOiBuLCAiZWxhcHNlZF9z"
    "ZWMiOiBlbGFwc2VkfQoKICAgIGV4Y2VwdCBhc3luY2lvLlRpbWVvdXRFcnJvcjoKICAgICAgICBl"
    "bGFwc2VkID0gcm91bmQodGltZS50aW1lKCkgLSB0MCwgMikKICAgICAgICBhdWRpdF9sb2dnZXIu"
    "aW5mbyhmIlRJTUVPVVR8e2VsYXBzZWR9c3x7dGFza1s6ODBdfSIpCiAgICAgICAgcmV0dXJuIHsi"
    "c3VjY2VzcyI6IEZhbHNlLAogICAgICAgICAgICAgICAgImVycm9yIjogZiJUYXNrIHRpbWVkIG91"
    "dCBhZnRlciB7VEFTS19USU1FT1VUfXMgKHtlbGFwc2VkfXMgZWxhcHNlZCkiLAogICAgICAgICAg"
    "ICAgICAgImVsYXBzZWRfc2VjIjogZWxhcHNlZH0KCiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6"
    "CiAgICAgICAgZWxhcHNlZCA9IHJvdW5kKHRpbWUudGltZSgpIC0gdDAsIDIpCiAgICAgICAgcmV0"
    "dXJuIHsic3VjY2VzcyI6IEZhbHNlLCAiZXJyb3IiOiBzdHIoZSksICJlbGFwc2VkX3NlYyI6IGVs"
    "YXBzZWR9CgogICAgZmluYWxseToKICAgICAgICBpZiBzZXNzaW9uOgogICAgICAgICAgICB0cnk6"
    "IGF3YWl0IGFzeW5jaW8ud2FpdF9mb3Ioc2Vzc2lvbi5jbG9zZSgpLCB0aW1lb3V0PTUpCiAgICAg"
    "ICAgICAgIGV4Y2VwdDogcGFzcwoKCiMg4pSA4pSAIOuplOuqqOumrC/tlZnsirUg7Iuc7Iqk7YWc"
    "IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgAppbXBvcnQganNvbiBhcyBfanNvbgpmcm9tIHBhdGhsaWIgaW1wb3J0"
    "IFBhdGggYXMgX1BhdGgKCk1FTU9SWV9GSUxFID0gX1BhdGgoIi9hcHAvZGF0YS91c2VyX21lbW9y"
    "eS5qc29uIikKQUxMT1dFRF9GSUxFX0VYVCA9IHsiLnR4dCIsIi5tZCIsIi5jc3YiLCIuanNvbiIs"
    "Ii5wZGYiLCIueGxzeCIsIi54bHMiLCIuZG9jeCIsIi5odG1sIiwiLnhtbCIsIi5sb2ciLCIucHki"
    "LCIuc2gifQpVU0VSX0ZJTEVTX0RJUiA9IF9QYXRoKCIvYXBwL2RhdGEvdXNlcl9maWxlcyIpCgpk"
    "ZWYgX2xvYWRfbWVtb3J5KCkgLT4gZGljdDoKICAgIHRyeToKICAgICAgICBpZiBNRU1PUllfRklM"
    "RS5leGlzdHMoKToKICAgICAgICAgICAgcmV0dXJuIF9qc29uLmxvYWRzKE1FTU9SWV9GSUxFLnJl"
    "YWRfdGV4dCgidXRmLTgiKSkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcGFzcwogICAg"
    "cmV0dXJuIHsibG9jYXRpb24iOiIiLCJpbnRlcmVzdHMiOltdLCJwcmVmZXJlbmNlcyI6e30sImZh"
    "Y3RzIjpbXSwicGFzdF9xdWVyaWVzIjpbXX0KCmRlZiBfc2F2ZV9tZW1vcnkobWVtOiBkaWN0KToK"
    "ICAgIHRyeToKICAgICAgICBNRU1PUllfRklMRS5wYXJlbnQubWtkaXIocGFyZW50cz1UcnVlLCBl"
    "eGlzdF9vaz1UcnVlKQogICAgICAgIE1FTU9SWV9GSUxFLndyaXRlX3RleHQoX2pzb24uZHVtcHMo"
    "bWVtLCBlbnN1cmVfYXNjaWk9RmFsc2UsIGluZGVudD0yKSwgInV0Zi04IikKICAgIGV4Y2VwdCBF"
    "eGNlcHRpb24gYXMgZToKICAgICAgICBsb2dnZXIuZXJyb3IoZiJNZW1vcnkgc2F2ZSBmYWlsZWQ6"
    "IHtlfSIpCgpkZWYgX3VwZGF0ZV9tZW1vcnlfZnJvbV90YXNrKHRhc2s6IHN0ciwgcmVzdWx0OiBz"
    "dHIpOgogICAgIiIi7J6R7JeFIOq4sOuhneyXkOyEnCDsnpDrj5nsnLzroZwg7IKs7Jqp7J6QIOyg"
    "leuztCDtlZnsirUiIiIKICAgIG1lbSA9IF9sb2FkX21lbW9yeSgpCiAgICAjIOy1nOq3vCDsv7zr"
    "pqwg7KCA7J6lICjstZzrjIAgNTDqsJwpCiAgICBtZW1bInBhc3RfcXVlcmllcyJdID0gbWVtLmdl"
    "dCgicGFzdF9xdWVyaWVzIiwgW10pWy00OTpdICsgWwogICAgICAgIHsidGFzayI6IHRhc2tbOjIw"
    "MF0sICJ0aW1lIjogZGF0ZXRpbWUubm93KCkuaXNvZm9ybWF0KCl9CiAgICBdCiAgICAjIOychOy5"
    "mCDsnpDrj5kg6rCQ7KeACiAgICBpbXBvcnQgcmUgYXMgX3JlMgogICAgbG9jX21hdGNoID0gX3Jl"
    "Mi5zZWFyY2gociIo7ISc7Jq4fOu2gOyCsHzrjIDqtax87J247LKcfOq0keyjvHzrjIDsoIR87Jq4"
    "7IKwfOyEuOyihXzsoJzso7x87IiY7JuQfOyEseuCqHzqs6DslpEpIiwgdGFzaykKICAgIGlmIGxv"
    "Y19tYXRjaCBhbmQgbm90IG1lbS5nZXQoImxvY2F0aW9uIik6CiAgICAgICAgbWVtWyJsb2NhdGlv"
    "biJdID0gbG9jX21hdGNoLmdyb3VwKDEpCiAgICAjIOq0gOyLrOyCrCDsnpDrj5kg6rCQ7KeACiAg"
    "ICBpbnRlcmVzdF9rZXl3b3JkcyA9IHsi7KO86rCAIjoi7KO87IudIiwi7ZmY7JyoIjoi6riI7Jy1"
    "Iiwi64Kg7JSoIjoi64Kg7JSoIiwi64m07IqkIjoi64m07IqkIiwKICAgICAgICAgICAgICAgICAg"
    "ICAgICAgICLqsIDqsqkiOiLsh7ztlZEiLCLtla3qs7UiOiLsl6ztlokiLCLrp5vsp5EiOiLsnYzs"
    "i50iLCLrtoDrj5nsgrAiOiLrtoDrj5nsgrAifQogICAgZm9yIGt3LCBpbnRlcmVzdCBpbiBpbnRl"
    "cmVzdF9rZXl3b3Jkcy5pdGVtcygpOgogICAgICAgIGlmIGt3IGluIHRhc2sgYW5kIGludGVyZXN0"
    "IG5vdCBpbiBtZW0uZ2V0KCJpbnRlcmVzdHMiLFtdKToKICAgICAgICAgICAgbWVtLnNldGRlZmF1"
    "bHQoImludGVyZXN0cyIsW10pLmFwcGVuZChpbnRlcmVzdCkKICAgICAgICAgICAgbWVtWyJpbnRl"
    "cmVzdHMiXSA9IG1lbVsiaW50ZXJlc3RzIl1bLTIwOl0KICAgIF9zYXZlX21lbW9yeShtZW0pCgpk"
    "ZWYgX2dldF9tZW1vcnlfY29udGV4dCgpIC0+IHN0cjoKICAgICIiIkxMTSDtlITroaztlITtirjs"
    "l5Ag7KO87J6F7ZWgIOuplOuqqOumrCDsu6jthY3siqTtirgiIiIKICAgIG1lbSA9IF9sb2FkX21l"
    "bW9yeSgpCiAgICBwYXJ0cyA9IFtdCiAgICBpZiBtZW0uZ2V0KCJsb2NhdGlvbiIpOgogICAgICAg"
    "IHBhcnRzLmFwcGVuZChmIlVzZXIgbG9jYXRpb246IHttZW1bJ2xvY2F0aW9uJ119IikKICAgIGlm"
    "IG1lbS5nZXQoImludGVyZXN0cyIpOgogICAgICAgIHBhcnRzLmFwcGVuZChmIlVzZXIgaW50ZXJl"
    "c3RzOiB7JywgJy5qb2luKG1lbVsnaW50ZXJlc3RzJ11bOjEwXSl9IikKICAgIGlmIG1lbS5nZXQo"
    "InByZWZlcmVuY2VzIik6CiAgICAgICAgcGFydHMuYXBwZW5kKGYiUHJlZmVyZW5jZXM6IHtfanNv"
    "bi5kdW1wcyhtZW1bJ3ByZWZlcmVuY2VzJ10sIGVuc3VyZV9hc2NpaT1GYWxzZSl9IikKICAgIGlm"
    "IG1lbS5nZXQoImZhY3RzIik6CiAgICAgICAgcGFydHMuYXBwZW5kKGYiS25vd24gZmFjdHM6IHsn"
    "OyAnLmpvaW4obWVtWydmYWN0cyddWy01Ol0pfSIpCiAgICByZXR1cm4gIlxuIi5qb2luKHBhcnRz"
    "KSBpZiBwYXJ0cyBlbHNlICIiCgojIOKUgOKUgCDroZzsu6wg7YyM7J28IOygkeq3vCDsi5zsiqTt"
    "hZwg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSACmRlZiBfc2FmZV9wYXRoKGZpbGVuYW1lOiBzdHIpIC0+IF9QYXRoOgogICAgIiIi"
    "6rK966GcIO2DiOy2nCDrsKnsp4AiIiIKICAgIGNsZWFuID0gX1BhdGgoZmlsZW5hbWUpLm5hbWUg"
    "ICMg65SU66CJ7Yag66asIO2DkOyDiSDssKjri6gKICAgIGlmICIuLiIgaW4gc3RyKGZpbGVuYW1l"
    "KSBvciAiLyIgaW4gZmlsZW5hbWUgb3IgIlxcIiBpbiBmaWxlbmFtZToKICAgICAgICByYWlzZSBW"
    "YWx1ZUVycm9yKCJJbnZhbGlkIGZpbGVuYW1lIikKICAgIHBhdGggPSBVU0VSX0ZJTEVTX0RJUiAv"
    "IGNsZWFuCiAgICBpZiBub3Qgc3RyKHBhdGgucmVzb2x2ZSgpKS5zdGFydHN3aXRoKHN0cihVU0VS"
    "X0ZJTEVTX0RJUi5yZXNvbHZlKCkpKToKICAgICAgICByYWlzZSBWYWx1ZUVycm9yKCJQYXRoIHRy"
    "YXZlcnNhbCBibG9ja2VkIikKICAgIGlmIHBhdGguc3VmZml4Lmxvd2VyKCkgbm90IGluIEFMTE9X"
    "RURfRklMRV9FWFQ6CiAgICAgICAgcmFpc2UgVmFsdWVFcnJvcihmIkV4dGVuc2lvbiBub3QgYWxs"
    "b3dlZDoge3BhdGguc3VmZml4fSIpCiAgICByZXR1cm4gcGF0aAoKIyDilIDilIAg7JeU65Oc7Y+s"
    "7J247Yq4IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApAYXBwLmdldCgi"
    "L2hlYWx0aCIpCmRlZiBoZWFsdGgoKToKICAgIG11bHRpX29rID0gRmFsc2UKICAgIHRyeToKICAg"
    "ICAgICBmcm9tIG11bHRpX2FnZW50LmdyYXBoIGltcG9ydCBidWlsZF9ncmFwaAogICAgICAgIG11"
    "bHRpX29rID0gVHJ1ZQogICAgZXhjZXB0IEV4Y2VwdGlvbjogcGFzcwogICAgcmV0dXJuIHsic3Rh"
    "dHVzIjogImhlYWx0aHkiIGlmIGxsbSBlbHNlICJub19hcGlfa2V5IiwKICAgICAgICAgICAgIm1v"
    "ZGVsIjogR1JPUV9NT0RFTCwgInZlcnNpb24iOiAiNi4xLjAiLAogICAgICAgICAgICAiZW5naW5l"
    "IjogImJyb3dzZXItdXNlIiwKICAgICAgICAgICAgIm11bHRpX2FnZW50IjogbXVsdGlfb2ssCiAg"
    "ICAgICAgICAgICJ0aW1lb3V0cyI6IHsidGFzayI6IFRBU0tfVElNRU9VVCwgIm11bHRpIjogTVVM"
    "VElfVElNRU9VVH0sCiAgICAgICAgICAgICJjb25jdXJyZW50IjogZiJ7X2FjdGl2ZV90YXNrc30v"
    "e01BWF9DT05DVVJSRU5UfSIsCiAgICAgICAgICAgICJtZW1vcnkiOiBNRU1PUllfRklMRS5leGlz"
    "dHMoKSwKICAgICAgICAgICAgInVzZXJfZmlsZXMiOiBVU0VSX0ZJTEVTX0RJUi5leGlzdHMoKX0K"
    "CkBhcHAuZ2V0KCIvaGVhbHRoL211bHRpIikKZGVmIGhlYWx0aF9tdWx0aSgpOgogICAgdHJ5Ogog"
    "ICAgICAgIGZyb20gbXVsdGlfYWdlbnQuZ3JhcGggaW1wb3J0IGJ1aWxkX2dyYXBoCiAgICAgICAg"
    "cmV0dXJuIHsibXVsdGlfYWdlbnRfZW5hYmxlZCI6IFRydWV9CiAgICBleGNlcHQgRXhjZXB0aW9u"
    "IGFzIGU6CiAgICAgICAgcmV0dXJuIHsibXVsdGlfYWdlbnRfZW5hYmxlZCI6IEZhbHNlLCAiZXJy"
    "b3IiOiBzdHIoZSl9CgpAYXBwLnBvc3QoIi9icm93c2UiLCByZXNwb25zZV9tb2RlbD1Ccm93c2VS"
    "ZXNwb25zZSkKQGxpbWl0ZXIubGltaXQoIjEwL21pbnV0ZSIpCmFzeW5jIGRlZiBicm93c2UocmVx"
    "dWVzdDogUmVxdWVzdCwgYm9keTogQnJvd3NlUmVxdWVzdCwKICAgICAgICAgICAgICAgICBfPURl"
    "cGVuZHModmVyaWZ5X2FwaV9rZXkpKToKICAgIGlmIG5vdCBsbG06CiAgICAgICAgcmFpc2UgSFRU"
    "UEV4Y2VwdGlvbig1MDAsICJObyBMTE0gY29uZmlndXJlZCDigJQgc2V0IEdST1FfQVBJX0tFWSwg"
    "T1BFTkFJX0FQSV9LRVksIEFOVEhST1BJQ19BUElfS0VZLCBvciBHT09HTEVfQVBJX0tFWSIpCgog"
    "ICAgIyDrqZTrqqjrpqwg7Luo7YWN7Iqk7Yq4IOyjvOyehQogICAgbWVtX2N0eCA9IF9nZXRfbWVt"
    "b3J5X2NvbnRleHQoKQogICAgcmF3X3Rhc2sgPSBib2R5LnRhc2sKICAgIGlmIG1lbV9jdHg6CiAg"
    "ICAgICAgZnVsbF90YXNrID0gZiJbVXNlciBjb250ZXh0OiB7bWVtX2N0eH1dXG57Ym9keS50YXNr"
    "fSIKICAgIGVsc2U6CiAgICAgICAgZnVsbF90YXNrID0gYm9keS50YXNrCiAgICBmdWxsX3Rhc2sg"
    "PSBhcHBseV9uYXZlcl9wcmlvcml0eShmdWxsX3Rhc2spCiAgICBpZiBib2R5LnVybDoKICAgICAg"
    "ICBmdWxsX3Rhc2sgPSBmIkdvIHRvIHtib2R5LnVybH0gZmlyc3QsIHRoZW4ge2JvZHkudGFza30i"
    "CgogICAgc3RlcHMgPSBib2R5Lm1heF9zdGVwcyBvciBNQVhfU1RFUFMKICAgIHZpc2lvbiA9IGJv"
    "ZHkudXNlX3Zpc2lvbiBpZiBib2R5LnVzZV92aXNpb24gaXMgbm90IE5vbmUgZWxzZSBVU0VfVklT"
    "SU9OCgogICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJCUk9XU0V8e3JlcXVlc3QuY2xpZW50Lmhvc3R9"
    "fHtmdWxsX3Rhc2tbOjEwMF19IikKCiAgICAjIOyalOyyreuzhCDtlITroZzrsJTsnbTrjZQg7Jik"
    "67KE65287J2065OcCiAgICBvdmVycmlkZV9sbG0gPSBOb25lCiAgICBpZiBib2R5LnByb3ZpZGVy"
    "IG9yIGJvZHkuYXBpX2tleToKICAgICAgICB0cnk6CiAgICAgICAgICAgIG92ZXJyaWRlX2xsbSA9"
    "IGNyZWF0ZV9sbG0oCiAgICAgICAgICAgICAgICBwcm92aWRlcj1ib2R5LnByb3ZpZGVyLAogICAg"
    "ICAgICAgICAgICAgYXBpX2tleT1ib2R5LmFwaV9rZXksCiAgICAgICAgICAgICAgICBtb2RlbD1i"
    "b2R5Lm1vZGVsCiAgICAgICAgICAgICkKICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAg"
    "ICAgICAgICAgIHJldHVybiBCcm93c2VSZXNwb25zZShzdWNjZXNzPUZhbHNlLCBlcnJvcj1mIkxM"
    "TSBvdmVycmlkZSBmYWlsZWQ6IHtlfSIsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
    "ICB0aW1lc3RhbXA9ZGF0ZXRpbWUubm93KCkuaXNvZm9ybWF0KCkpCgogICAgYXN5bmMgd2l0aCB0"
    "YXNrX3Nsb3QoKToKICAgICAgICByZXN1bHQgPSBhd2FpdCBfcnVuX2FnZW50KGZ1bGxfdGFzaywg"
    "c3RlcHMsIHZpc2lvbiwgb3ZlcnJpZGVfbGxtKQoKICAgICAgICAjIFtBTlRJLUxPT1BdIFNlbGYt"
    "SGVhbGluZzog7YOA7J6E7JWE7JuDL+uEpOu5hOqyjOydtOyFmCDsl5Drn6wg7IucIDHtmozrp4wg"
    "7J6s7Iuc64+ECiAgICAgICAgaWYgbm90IHJlc3VsdFsic3VjY2VzcyJdOgogICAgICAgICAgICBl"
    "cnIgPSByZXN1bHQuZ2V0KCJlcnJvciIsICIiKS5sb3dlcigpCiAgICAgICAgICAgIHJldHJ5YWJs"
    "ZSA9IGFueShrIGluIGVyciBmb3IgayBpbgogICAgICAgICAgICAgICAgWyJ0aW1lb3V0IiwgIm5h"
    "dmlnYXRpb24iLCAidGFyZ2V0IGNsb3NlZCIsICJzZXNzaW9uIGNsb3NlZCJdKQogICAgICAgICAg"
    "ICBpZiByZXRyeWFibGU6CiAgICAgICAgICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIlJFVFJZ"
    "fHtyZXF1ZXN0LmNsaWVudC5ob3N0fSIpCiAgICAgICAgICAgICAgICByZXRyeSA9IGF3YWl0IF9y"
    "dW5fYWdlbnQoZnVsbF90YXNrLCBtYXgoc3RlcHMvLzIsIDUpLCB2aXNpb24sIG92ZXJyaWRlX2xs"
    "bSkKICAgICAgICAgICAgICAgIGlmIHJldHJ5WyJzdWNjZXNzIl06CiAgICAgICAgICAgICAgICAg"
    "ICAgcmV0cnlbInN1bW1hcnkiXSA9IGYiW3JldHJ5XSB7cmV0cnkuZ2V0KCdzdW1tYXJ5JywnJyl9"
    "IgogICAgICAgICAgICAgICAgICAgIHJlc3VsdCA9IHJldHJ5CgogICAgICAgIGlmIHJlc3VsdFsi"
    "c3VjY2VzcyJdOgogICAgICAgICAgICBfdXBkYXRlX21lbW9yeV9mcm9tX3Rhc2socmF3X3Rhc2ss"
    "IHJlc3VsdC5nZXQoInN1bW1hcnkiLCIiKSkKICAgICAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8o"
    "ZiJCUk9XU0VfT0t8c3RlcHM9e3Jlc3VsdFsnc3RlcHNfdGFrZW4nXX18e3Jlc3VsdFsnZWxhcHNl"
    "ZF9zZWMnXX1zIikKICAgICAgICBlbHNlOgogICAgICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbyhm"
    "IkJST1dTRV9GQUlMfHtyZXN1bHQuZ2V0KCdlcnJvcicsJycpWzoyMDBdfSIpCgogICAgICAgIHJl"
    "dHVybiBCcm93c2VSZXNwb25zZSgKICAgICAgICAgICAgKipyZXN1bHQsCiAgICAgICAgICAgIHRp"
    "bWVzdGFtcD1kYXRldGltZS5ub3coKS5pc29mb3JtYXQoKQogICAgICAgICkKCgojIOKUgOKUgCDr"
    "qYDti7Dtg60g67iM65287Jqw7KaIIOyXlOuTnO2PrOyduO2KuCDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKQGFwcC5wb3N0KCIvYnJvd3NlL211bHRp"
    "dGFiIikKQGxpbWl0ZXIubGltaXQoIjUvbWludXRlIikKYXN5bmMgZGVmIGJyb3dzZV9tdWx0aXRh"
    "YihyZXF1ZXN0OiBSZXF1ZXN0LCBib2R5OiBNdWx0aVRhYlJlcXVlc3QsCiAgICAgICAgICAgICAg"
    "ICAgICAgICAgICAgXz1EZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAgICAiIiLsl6zrn6wg7IKs"
    "7J207Yq466W8IOyInOywqOyggeycvOuhnCDrsKnrrLjtlZjqs6Ag6rKw6rO866W8IOyihe2VqSDr"
    "uYTqtZAiIiIKICAgIGlmIG5vdCBsbG06CiAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbig1MDAs"
    "ICJObyBMTE0gY29uZmlndXJlZCIpCgogICAgIyBHcm9xIOustOujjCDrqqjrjbgg6rK96rOgCiAg"
    "ICBhY3RpdmVfbGxtID0gbGxtCiAgICBpZiBib2R5LnByb3ZpZGVyIG9yIGJvZHkuYXBpX2tleToK"
    "ICAgICAgICB0cnk6CiAgICAgICAgICAgIGFjdGl2ZV9sbG0gPSBjcmVhdGVfbGxtKHByb3ZpZGVy"
    "PWJvZHkucHJvdmlkZXIsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBhcGlf"
    "a2V5PWJvZHkuYXBpX2tleSwgbW9kZWw9Ym9keS5tb2RlbCkKICAgICAgICBleGNlcHQgRXhjZXB0"
    "aW9uIGFzIGU6CiAgICAgICAgICAgIHJldHVybiB7InN1Y2Nlc3MiOiBGYWxzZSwgImVycm9yIjog"
    "ZiJMTE0gb3ZlcnJpZGUgZmFpbGVkOiB7ZX0ifQoKICAgIGlmIGdldGF0dHIoYWN0aXZlX2xsbSwg"
    "InByb3ZpZGVyIiwgIiIpID09ICJncm9xIjoKICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbygiTVVM"
    "VElUQUJfV0FSTnxncm9xX3Byb3ZpZGVyX3VzZWQiKQoKICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYi"
    "TVVMVElUQUJ8e3JlcXVlc3QuY2xpZW50Lmhvc3R9fHRhYnM9e2xlbihib2R5LnVybHMpfXx7Ym9k"
    "eS50YXNrWzo4MF19IikKCiAgICAjIFVSTOydtCDsl4bsnLzrqbQg7J6R7JeF7JeQ7IScIOyekOuP"
    "mSDstpTstpwg7Iuc64+ECiAgICB1cmxzID0gYm9keS51cmxzCiAgICBpZiBub3QgdXJsczoKICAg"
    "ICAgICAjIExMTeyXkOqyjCBVUkwg7LaU7LacIOyalOyyrQogICAgICAgIGV4dHJhY3RfdGFzayA9"
    "IGYi64uk7J2MIOyekeyXheydhCDsiJjtlontlZjquLAg7JyE7ZW0IOuwqeusuO2VoCDsm7nsgqzs"
    "nbTtirggVVJM7J2EIOy1nOuMgCAz6rCcIOy2lOyynO2VtOykmCAoVVJM66eMIO2VnCDspITsl5Ag"
    "7ZWY64KY7JSpKToge2JvZHkudGFza30iCiAgICAgICAgdHJ5OgogICAgICAgICAgICBmcm9tIGxh"
    "bmdjaGFpbl9jb3JlLm1lc3NhZ2VzIGltcG9ydCBIdW1hbk1lc3NhZ2UKICAgICAgICAgICAgcmVz"
    "cCA9IGF3YWl0IGFjdGl2ZV9sbG0uYWludm9rZShbSHVtYW5NZXNzYWdlKGNvbnRlbnQ9ZXh0cmFj"
    "dF90YXNrKV0pCiAgICAgICAgICAgIGltcG9ydCByZSBhcyBfcmUzCiAgICAgICAgICAgIGZvdW5k"
    "X3VybHMgPSBfcmUzLmZpbmRhbGwocidodHRwcz86Ly9bXlxzPD4iXSsnLCByZXNwLmNvbnRlbnQp"
    "CiAgICAgICAgICAgIHVybHMgPSBmb3VuZF91cmxzWzo1XQogICAgICAgIGV4Y2VwdCBFeGNlcHRp"
    "b246CiAgICAgICAgICAgIHVybHMgPSBbXQoKICAgIGlmIG5vdCB1cmxzOgogICAgICAgICMg64Sk"
    "7J2067KEIOqygOyDieycvOuhnCDtj7TrsLEKICAgICAgICB1cmxzID0gW2YiaHR0cHM6Ly9zZWFy"
    "Y2gubmF2ZXIuY29tL3NlYXJjaC5uYXZlcj9xdWVyeT17Ym9keS50YXNrfSJdCgogICAgIyDqsIEg"
    "7YOtKFVSTCnrs4TroZwg7Iic7LCoIOyLpO2WiQogICAgdGFiX3Jlc3VsdHMgPSBbXQogICAgYXN5"
    "bmMgd2l0aCB0YXNrX3Nsb3QoKToKICAgICAgICBmb3IgaSwgdXJsIGluIGVudW1lcmF0ZSh1cmxz"
    "Wzo1XSk6CiAgICAgICAgICAgIHRhYl90YXNrID0gZiJHbyB0byB7dXJsfSBhbmQgZmluZCBpbmZv"
    "cm1hdGlvbiBhYm91dDoge2JvZHkudGFza30uIEV4dHJhY3Qga2V5IGRhdGEgY29uY2lzZWx5LiIK"
    "ICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgc2Vzc2lvbiA9IEJyb3dzZXJTZXNzaW9u"
    "KGJyb3dzZXJfcHJvZmlsZT1Ccm93c2VyUHJvZmlsZSgKICAgICAgICAgICAgICAgICAgICBoZWFk"
    "bGVzcz1UcnVlLCBkaXNhYmxlX3NlY3VyaXR5PUZhbHNlLAogICAgICAgICAgICAgICAgICAgIHZp"
    "ZXdwb3J0PXsid2lkdGgiOiAxMjgwLCAiaGVpZ2h0IjogNzIwfSkpCiAgICAgICAgICAgICAgICBh"
    "Z2VudCA9IEFnZW50KHRhc2s9dGFiX3Rhc2ssIGxsbT1hY3RpdmVfbGxtLAogICAgICAgICAgICAg"
    "ICAgICAgICAgICAgICAgICBicm93c2VyX3Nlc3Npb249c2Vzc2lvbiwKICAgICAgICAgICAgICAg"
    "ICAgICAgICAgICAgICAgdXNlX3Zpc2lvbj1GYWxzZSwgbWF4X2FjdGlvbnNfcGVyX3N0ZXA9MykK"
    "ICAgICAgICAgICAgICAgIHJlc3VsdCA9IGF3YWl0IGFzeW5jaW8ud2FpdF9mb3IoCiAgICAgICAg"
    "ICAgICAgICAgICAgYWdlbnQucnVuKG1heF9zdGVwcz1ib2R5Lm1heF9zdGVwc19wZXJfdGFiKSwK"
    "ICAgICAgICAgICAgICAgICAgICB0aW1lb3V0PVRBU0tfVElNRU9VVAogICAgICAgICAgICAgICAg"
    "KQogICAgICAgICAgICAgICAgZmluYWwgPSByZXN1bHQuZmluYWxfcmVzdWx0KCkgaWYgcmVzdWx0"
    "IGVsc2UgIlvqsrDqs7zsl4bsnYxdIgogICAgICAgICAgICAgICAgdGFiX3Jlc3VsdHMuYXBwZW5k"
    "KHsidGFiIjogaSsxLCAidXJsIjogdXJsLCAicmVzdWx0IjogZmluYWxbOjMwMDBdLCAic3VjY2Vz"
    "cyI6IFRydWV9KQogICAgICAgICAgICBleGNlcHQgYXN5bmNpby5UaW1lb3V0RXJyb3I6CiAgICAg"
    "ICAgICAgICAgICB0YWJfcmVzdWx0cy5hcHBlbmQoeyJ0YWIiOiBpKzEsICJ1cmwiOiB1cmwsICJy"
    "ZXN1bHQiOiAiW+2DgOyehOyVhOybg10iLCAic3VjY2VzcyI6IEZhbHNlfSkKICAgICAgICAgICAg"
    "ZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgICAgICAgICAgdGFiX3Jlc3VsdHMuYXBwZW5k"
    "KHsidGFiIjogaSsxLCAidXJsIjogdXJsLCAicmVzdWx0IjogZiJb7Jik66WYOiB7c3RyKGUpWzoy"
    "MDBdfV0iLCAic3VjY2VzcyI6IEZhbHNlfSkKICAgICAgICAgICAgZmluYWxseToKICAgICAgICAg"
    "ICAgICAgIHRyeToKICAgICAgICAgICAgICAgICAgICBpZiAnc2Vzc2lvbicgaW4gbG9jYWxzKCk6"
    "IGF3YWl0IGFzeW5jaW8ud2FpdF9mb3Ioc2Vzc2lvbi5jbG9zZSgpLCB0aW1lb3V0PTUpCiAgICAg"
    "ICAgICAgICAgICBleGNlcHQ6IHBhc3MKCiAgICAgICAgIyDqsrDqs7wg7KKF7ZWpIOu5hOq1kAog"
    "ICAgICAgIGNvbXBhcmVfcHJvbXB0ID0gZiLri6TsnYzsnYAg7Jes65+sIOyCrOydtO2KuOyXkOyE"
    "nCDsiJjsp5HtlZwg6rKw6rO87J6F64uI64ukLiAne2JvZHkudGFza30n7JeQIOuMgO2VtCDsooXt"
    "lakg67mE6rWQIOu2hOyEne2VtOyjvOyEuOyalDpcblxuIgogICAgICAgIGZvciB0ciBpbiB0YWJf"
    "cmVzdWx0czoKICAgICAgICAgICAgY29tcGFyZV9wcm9tcHQgKz0gZiJb7YOte3RyWyd0YWInXX0g"
    "LSB7dHJbJ3VybCddfV1cbnt0clsncmVzdWx0J119XG5cbiIKICAgICAgICBjb21wYXJlX3Byb21w"
    "dCArPSAi7JyEIOqysOqzvOulvCDruYTqtZAg67aE7ISd7ZWY6rOgLCDtlbXsi6zsnYQg7ZWc6rWt"
    "7Ja066GcIOygleumrO2VtOyjvOyEuOyalC4iCgogICAgICAgIHRyeToKICAgICAgICAgICAgZnJv"
    "bSBsYW5nY2hhaW5fY29yZS5tZXNzYWdlcyBpbXBvcnQgSHVtYW5NZXNzYWdlCiAgICAgICAgICAg"
    "IHN1bW1hcnkgPSBhd2FpdCBhc3luY2lvLndhaXRfZm9yKAogICAgICAgICAgICAgICAgYWN0aXZl"
    "X2xsbS5haW52b2tlKFtIdW1hbk1lc3NhZ2UoY29udGVudD1jb21wYXJlX3Byb21wdCldKSwKICAg"
    "ICAgICAgICAgICAgIHRpbWVvdXQ9NjAKICAgICAgICAgICAgKQogICAgICAgICAgICBmaW5hbF9z"
    "dW1tYXJ5ID0gc3VtbWFyeS5jb250ZW50CiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgog"
    "ICAgICAgICAgICBmaW5hbF9zdW1tYXJ5ID0gIlxuLS0tXG4iLmpvaW4oW2YiW+2DrXtyWyd0YWIn"
    "XX1dIHtyWydyZXN1bHQnXVs6NTAwXX0iIGZvciByIGluIHRhYl9yZXN1bHRzXSkKCiAgICAjIOup"
    "lOuqqOumrCDsl4XrjbDsnbTtirgKICAgIF91cGRhdGVfbWVtb3J5X2Zyb21fdGFzayhib2R5LnRh"
    "c2ssIGZpbmFsX3N1bW1hcnlbOjUwMF0pCiAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIk1VTFRJVEFC"
    "X09LfHRhYnM9e2xlbih0YWJfcmVzdWx0cyl9IikKCiAgICByZXR1cm4gewogICAgICAgICJzdWNj"
    "ZXNzIjogVHJ1ZSwKICAgICAgICAic3VtbWFyeSI6IGZpbmFsX3N1bW1hcnksCiAgICAgICAgInRh"
    "YnMiOiB0YWJfcmVzdWx0cywKICAgICAgICAidGFiX2NvdW50IjogbGVuKHRhYl9yZXN1bHRzKSwK"
    "ICAgICAgICAidGltZXN0YW1wIjogZGF0ZXRpbWUubm93KCkuaXNvZm9ybWF0KCkKICAgIH0KCiMg"
    "TXVsdGktQWdlbnQg7JeU65Oc7Y+s7J247Yq4CkBhcHAucG9zdCgiL2Jyb3dzZS9tdWx0aSIpCkBs"
    "aW1pdGVyLmxpbWl0KCI1L21pbnV0ZSIpCmFzeW5jIGRlZiBicm93c2VfbXVsdGkocmVxdWVzdDog"
    "UmVxdWVzdCwgYm9keTogQnJvd3NlUmVxdWVzdCwKICAgICAgICAgICAgICAgICAgICAgICBfPURl"
    "cGVuZHModmVyaWZ5X2FwaV9rZXkpKToKICAgIHRyeToKICAgICAgICBmcm9tIG11bHRpX2FnZW50"
    "LmdyYXBoIGltcG9ydCBidWlsZF9ncmFwaAogICAgICAgIGZyb20gbXVsdGlfYWdlbnQuZ3JvcV91"
    "dGlscyBpbXBvcnQgVG9rZW5UcmFja2VyCiAgICBleGNlcHQgSW1wb3J0RXJyb3I6CiAgICAgICAg"
    "cmFpc2UgSFRUUEV4Y2VwdGlvbig1MDEsICJNdWx0aS1BZ2VudCBub3QgYXZhaWxhYmxlIChHUk9R"
    "X0FQSV9LRVkgcmVxdWlyZWQpIikKCiAgICAjIFtCVURHRVRdIOyalOyyreuzhCDruYTsmqkg7IOB"
    "7ZWcLiDrr7jsp4DsoJUg7IucIE1VTFRJX0JVREdFVF9VU0Qo6riw67O4IDA966y07KCc7ZWcKS4K"
    "ICAgIF9idWRnZXQgPSBib2R5LmJ1ZGdldF91c2QgaWYgYm9keS5idWRnZXRfdXNkIGlzIG5vdCBO"
    "b25lIGVsc2UgTVVMVElfQlVER0VUX1VTRAogICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJNVUxUSXx7"
    "cmVxdWVzdC5jbGllbnQuaG9zdH18YnVkZ2V0PSR7X2J1ZGdldDouNGZ9fHtib2R5LnRhc2tbOjEw"
    "MF19IikKCiAgICBhc3luYyB3aXRoIHRhc2tfc2xvdCgpOgogICAgICAgIHRyeToKICAgICAgICAg"
    "ICAgZ3JhcGggPSBidWlsZF9ncmFwaCgpCiAgICAgICAgICAgIF90cmFja2VyID0gVG9rZW5UcmFj"
    "a2VyKGJ1ZGdldD1fYnVkZ2V0KQogICAgICAgICAgICBzdGF0ZSA9IHsib3JpZ2luYWxfdGFzayI6"
    "IGJvZHkudGFzaywgIm1lc3NhZ2VzIjogW10sCiAgICAgICAgICAgICAgICAgICAgICJyZXNlYXJj"
    "aF9yZXN1bHRzIjogW10sICJicm93c2VyX3Jlc3VsdHMiOiBbXSwKICAgICAgICAgICAgICAgICAg"
    "ICAgIml0ZXJhdGlvbiI6IDAsICJyb3V0ZV9oaXN0b3J5IjogW10sICJuZXh0IjogInN1cGVydmlz"
    "b3IiLAogICAgICAgICAgICAgICAgICAgICAidG9rZW5fdHJhY2tlciI6IF90cmFja2VyfQoKICAg"
    "ICAgICAgICAgIyBbQU5USS1MT09QXSBNdWx0aS1BZ2VudCDsoITssrQg7YOA7J6E7JWE7JuDCiAg"
    "ICAgICAgICAgIGZpbmFsID0gYXdhaXQgYXN5bmNpby53YWl0X2ZvcigKICAgICAgICAgICAgICAg"
    "IGdyYXBoLmFpbnZva2Uoc3RhdGUpLAogICAgICAgICAgICAgICAgdGltZW91dD1NVUxUSV9USU1F"
    "T1VUCiAgICAgICAgICAgICkKCiAgICAgICAgICAgIG1zZ3MgPSBmaW5hbC5nZXQoIm1lc3NhZ2Vz"
    "IiwgW10pCiAgICAgICAgICAgIGxhc3QgPSBtc2dzWy0xXS5jb250ZW50IGlmIG1zZ3MgZWxzZSAi"
    "bm8gcmVzdWx0IgogICAgICAgICAgICB0b2tlbl9pbmZvID0ge30KICAgICAgICAgICAgaWYgInRv"
    "a2VuX3RyYWNrZXIiIGluIGZpbmFsIGFuZCBmaW5hbFsidG9rZW5fdHJhY2tlciJdOgogICAgICAg"
    "ICAgICAgICAgdG9rZW5faW5mbyA9IGZpbmFsWyJ0b2tlbl90cmFja2VyIl0uc3VtbWFyeQogICAg"
    "ICAgICAgICBlbGlmIF90cmFja2VyOgogICAgICAgICAgICAgICAgdG9rZW5faW5mbyA9IF90cmFj"
    "a2VyLnN1bW1hcnkKCiAgICAgICAgICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiTVVMVElfT0t8dG9r"
    "ZW5zPXt0b2tlbl9pbmZvLmdldCgndG90YWxfdG9rZW5zJywwKX0iKQogICAgICAgICAgICByZXR1"
    "cm4geyJzdWNjZXNzIjogVHJ1ZSwgInJlc3VsdCI6IGxhc3QsCiAgICAgICAgICAgICAgICAgICAg"
    "InRva2VuX3VzYWdlIjogdG9rZW5faW5mbywKICAgICAgICAgICAgICAgICAgICAidGltZXN0YW1w"
    "IjogZGF0ZXRpbWUubm93KCkuaXNvZm9ybWF0KCl9CgogICAgICAgIGV4Y2VwdCBhc3luY2lvLlRp"
    "bWVvdXRFcnJvcjoKICAgICAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJNVUxUSV9USU1FT1VU"
    "fHtNVUxUSV9USU1FT1VUfXMiKQogICAgICAgICAgICByZXR1cm4geyJzdWNjZXNzIjogRmFsc2Us"
    "CiAgICAgICAgICAgICAgICAgICAgImVycm9yIjogZiJNdWx0aS1BZ2VudCB0aW1lZCBvdXQgYWZ0"
    "ZXIge01VTFRJX1RJTUVPVVR9cyIsCiAgICAgICAgICAgICAgICAgICAgInRpbWVzdGFtcCI6IGRh"
    "dGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpfQogICAgICAgIGV4Y2VwdCBSdW50aW1lRXJyb3IgYXMg"
    "ZToKICAgICAgICAgICAgaWYgIuyYiOyCsOy0iOqzvCIgaW4gc3RyKGUpIG9yICJidWRnZXQiIGlu"
    "IHN0cihlKS5sb3dlcigpOgogICAgICAgICAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJNVUxU"
    "SV9CVURHRVRfRVhDRUVERUR8JHtfdHJhY2tlci5jb3N0Oi40Zn0vJHtfYnVkZ2V0Oi40Zn0iKQog"
    "ICAgICAgICAgICAgICAgcmV0dXJuIHsic3VjY2VzcyI6IEZhbHNlLAogICAgICAgICAgICAgICAg"
    "ICAgICAgICAiZXJyb3IiOiBmIuu5hOyaqSDsg4HtlZwoJHtfYnVkZ2V0Oi40Zn0pIOy0iOqzvOuh"
    "nCDspJHri6jrkJjsl4jsirXri4jri6QuIiwKICAgICAgICAgICAgICAgICAgICAgICAgInRva2Vu"
    "X3VzYWdlIjogX3RyYWNrZXIuc3VtbWFyeSwKICAgICAgICAgICAgICAgICAgICAgICAgInRpbWVz"
    "dGFtcCI6IGRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpfQogICAgICAgICAgICBhdWRpdF9sb2dn"
    "ZXIuaW5mbyhmIk1VTFRJX0ZBSUx8e2V9IikKICAgICAgICAgICAgcmV0dXJuIHsic3VjY2VzcyI6"
    "IEZhbHNlLCAiZXJyb3IiOiBzdHIoZSksCiAgICAgICAgICAgICAgICAgICAgInRpbWVzdGFtcCI6"
    "IGRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpfQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMg"
    "ZToKICAgICAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJNVUxUSV9GQUlMfHtlfSIpCiAgICAg"
    "ICAgICAgIHJldHVybiB7InN1Y2Nlc3MiOiBGYWxzZSwgImVycm9yIjogc3RyKGUpLAogICAgICAg"
    "ICAgICAgICAgICAgICJ0aW1lc3RhbXAiOiBkYXRldGltZS5ub3coKS5pc29mb3JtYXQoKX0KCgoK"
    "IyDilIDilIAg66mU66qo66asIOyXlOuTnO2PrOyduO2KuCDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKQGFw"
    "cC5nZXQoIi9tZW1vcnkiKQphc3luYyBkZWYgZ2V0X21lbW9yeShfPURlcGVuZHModmVyaWZ5X2Fw"
    "aV9rZXkpKToKICAgIHJldHVybiBfbG9hZF9tZW1vcnkoKQoKQGFwcC5wb3N0KCIvbWVtb3J5IikK"
    "YXN5bmMgZGVmIHVwZGF0ZV9tZW1vcnkocmVxdWVzdDogUmVxdWVzdCwgXz1EZXBlbmRzKHZlcmlm"
    "eV9hcGlfa2V5KSk6CiAgICBib2R5ID0gYXdhaXQgcmVxdWVzdC5qc29uKCkKICAgIG1lbSA9IF9s"
    "b2FkX21lbW9yeSgpCiAgICBpZiAibG9jYXRpb24iIGluIGJvZHk6IG1lbVsibG9jYXRpb24iXSA9"
    "IHN0cihib2R5WyJsb2NhdGlvbiJdKVs6NTBdCiAgICBpZiAiaW50ZXJlc3RzIiBpbiBib2R5OiBt"
    "ZW1bImludGVyZXN0cyJdID0gW3N0cihpKVs6MzBdIGZvciBpIGluIGJvZHlbImludGVyZXN0cyJd"
    "WzoyMF1dCiAgICBpZiAicHJlZmVyZW5jZXMiIGluIGJvZHk6IG1lbVsicHJlZmVyZW5jZXMiXS51"
    "cGRhdGUoYm9keVsicHJlZmVyZW5jZXMiXSkKICAgIGlmICJmYWN0cyIgaW4gYm9keTogbWVtWyJm"
    "YWN0cyJdID0gKG1lbS5nZXQoImZhY3RzIixbXSkgKyBbc3RyKGYpWzoyMDBdIGZvciBmIGluIGJv"
    "ZHlbImZhY3RzIl1dKVstMzA6XQogICAgX3NhdmVfbWVtb3J5KG1lbSkKICAgIGF1ZGl0X2xvZ2dl"
    "ci5pbmZvKGYiTUVNT1JZX1VQREFURXx7bGlzdChib2R5LmtleXMoKSl9IikKICAgIHJldHVybiB7"
    "InN1Y2Nlc3MiOiBUcnVlLCAibWVtb3J5IjogbWVtfQoKQGFwcC5kZWxldGUoIi9tZW1vcnkiKQph"
    "c3luYyBkZWYgY2xlYXJfbWVtb3J5KF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkpOgogICAgX3Nh"
    "dmVfbWVtb3J5KHsibG9jYXRpb24iOiIiLCJpbnRlcmVzdHMiOltdLCJwcmVmZXJlbmNlcyI6e30s"
    "ImZhY3RzIjpbXSwicGFzdF9xdWVyaWVzIjpbXX0pCiAgICByZXR1cm4geyJzdWNjZXNzIjogVHJ1"
    "ZSwgIm1lc3NhZ2UiOiAiTWVtb3J5IGNsZWFyZWQifQoKIyDilIDilIAg7YyM7J28IOygkeq3vCDs"
    "l5Trk5ztj6zsnbjtirgg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACkBhcHAuZ2V0KCIvZmlsZXMiKQphc3luYyBkZWYgbGlz"
    "dF9maWxlcyhfPURlcGVuZHModmVyaWZ5X2FwaV9rZXkpKToKICAgIGlmIG5vdCBVU0VSX0ZJTEVT"
    "X0RJUi5leGlzdHMoKToKICAgICAgICByZXR1cm4geyJmaWxlcyI6IFtdLCAibWVzc2FnZSI6ICJO"
    "byB1c2VyX2ZpbGVzIGRpcmVjdG9yeSJ9CiAgICBmaWxlcyA9IFtdCiAgICBmb3IgZiBpbiBzb3J0"
    "ZWQoVVNFUl9GSUxFU19ESVIuaXRlcmRpcigpKToKICAgICAgICBpZiBmLmlzX2ZpbGUoKSBhbmQg"
    "Zi5zdWZmaXgubG93ZXIoKSBpbiBBTExPV0VEX0ZJTEVfRVhUOgogICAgICAgICAgICBmaWxlcy5h"
    "cHBlbmQoeyJuYW1lIjogZi5uYW1lLCAic2l6ZSI6IGYuc3RhdCgpLnN0X3NpemUsCiAgICAgICAg"
    "ICAgICAgICAgICAgICAgICAgIm1vZGlmaWVkIjogZGF0ZXRpbWUuZnJvbXRpbWVzdGFtcChmLnN0"
    "YXQoKS5zdF9tdGltZSkuaXNvZm9ybWF0KCl9KQogICAgcmV0dXJuIHsiZmlsZXMiOiBmaWxlcywg"
    "ImNvdW50IjogbGVuKGZpbGVzKX0KCkBhcHAuZ2V0KCIvZmlsZXMve2ZpbGVuYW1lfSIpCmFzeW5j"
    "IGRlZiByZWFkX2ZpbGUoZmlsZW5hbWU6IHN0ciwgXz1EZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6"
    "CiAgICB0cnk6CiAgICAgICAgcGF0aCA9IF9zYWZlX3BhdGgoZmlsZW5hbWUpCiAgICAgICAgaWYg"
    "bm90IHBhdGguZXhpc3RzKCk6CiAgICAgICAgICAgIHJhaXNlIEhUVFBFeGNlcHRpb24oNDA0LCBm"
    "IkZpbGUgbm90IGZvdW5kOiB7ZmlsZW5hbWV9IikKICAgICAgICBpZiBwYXRoLnN1ZmZpeC5sb3dl"
    "cigpIGluICgiLnBkZiIsICIueGxzeCIsICIueGxzIiwgIi5kb2N4Iik6CiAgICAgICAgICAgIHJl"
    "dHVybiB7Im5hbWUiOiBmaWxlbmFtZSwgInR5cGUiOiBwYXRoLnN1ZmZpeCwKICAgICAgICAgICAg"
    "ICAgICAgICAibWVzc2FnZSI6ICJCaW5hcnkgZmlsZSDigJQgdXNlIC9icm93c2UgdG8gYXNrIEFJ"
    "IHRvIGFuYWx5emUgaXQifQogICAgICAgIHRleHQgPSBwYXRoLnJlYWRfdGV4dCgidXRmLTgiLCBl"
    "cnJvcnM9InJlcGxhY2UiKVs6NTAwMDBdCiAgICAgICAgcmV0dXJuIHsibmFtZSI6IGZpbGVuYW1l"
    "LCAiY29udGVudCI6IHRleHQsICJzaXplIjogbGVuKHRleHQpfQogICAgZXhjZXB0IFZhbHVlRXJy"
    "b3IgYXMgZToKICAgICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKDQwMCwgc3RyKGUpKQoKQGFwcC5w"
    "b3N0KCIvZmlsZXMve2ZpbGVuYW1lfSIpCkBsaW1pdGVyLmxpbWl0KCIxMC9taW51dGUiKQphc3lu"
    "YyBkZWYgd3JpdGVfZmlsZShyZXF1ZXN0OiBSZXF1ZXN0LCBmaWxlbmFtZTogc3RyLCBfPURlcGVu"
    "ZHModmVyaWZ5X2FwaV9rZXkpKToKICAgIHRyeToKICAgICAgICBwYXRoID0gX3NhZmVfcGF0aChm"
    "aWxlbmFtZSkKICAgICAgICBib2R5ID0gYXdhaXQgcmVxdWVzdC5qc29uKCkKICAgICAgICB0ZXh0"
    "ID0gc3RyKGJvZHkuZ2V0KCJjb250ZW50IiwgIiIpKVs6MTAwMDAwXQogICAgICAgIFVTRVJfRklM"
    "RVNfRElSLm1rZGlyKHBhcmVudHM9VHJ1ZSwgZXhpc3Rfb2s9VHJ1ZSkKICAgICAgICBwYXRoLndy"
    "aXRlX3RleHQodGV4dCwgInV0Zi04IikKICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIkZJTEVf"
    "V1JJVEV8e2ZpbGVuYW1lfXx7bGVuKHRleHQpfWJ5dGVzIikKICAgICAgICByZXR1cm4geyJzdWNj"
    "ZXNzIjogVHJ1ZSwgIm5hbWUiOiBmaWxlbmFtZSwgInNpemUiOiBsZW4odGV4dCl9CiAgICBleGNl"
    "cHQgVmFsdWVFcnJvciBhcyBlOgogICAgICAgIHJhaXNlIEhUVFBFeGNlcHRpb24oNDAwLCBzdHIo"
    "ZSkpCgojIFtTRUNVUklUWV0g7IOB7YOcIO2ZleyduOyaqSAo6rSA66as7J6QIOyghOyaqSkKQGFw"
    "cC5nZXQoIi9tZXRyaWNzIikKYXN5bmMgZGVmIG1ldHJpY3MocmVxdWVzdDogUmVxdWVzdCwgXz1E"
    "ZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAgICByZXR1cm4gewogICAgICAgICJhY3RpdmVfdGFz"
    "a3MiOiBfYWN0aXZlX3Rhc2tzLAogICAgICAgICJtYXhfY29uY3VycmVudCI6IE1BWF9DT05DVVJS"
    "RU5ULAogICAgICAgICJtb2RlbCI6IEdST1FfTU9ERUwsCiAgICAgICAgInRpbWVvdXRzIjogewog"
    "ICAgICAgICAgICAidGFzayI6IFRBU0tfVElNRU9VVCwKICAgICAgICAgICAgIm11bHRpIjogTVVM"
    "VElfVElNRU9VVCwKICAgICAgICAgICAgInN0ZXAiOiBTVEVQX1RJTUVPVVQKICAgICAgICB9CiAg"
    "ICB9CgojIOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV"
    "kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV"
    "kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV"
    "kOKVkOKVkOKVkOKVkOKVkAojIFt2N10g6rKA7IOJIOyXlOuTnO2PrOyduO2KuCDigJQg64Sk7J20"
    "67KEIFNlYXJjaCBBUEkg7KCE7JqpICjruIzrnbzsmrDsp5Ug64yA7LK0KQojIOq4sOyhtCDrs7Ts"
    "lYgg6rOE7Li1IOyDgeyGjTogdmVyaWZ5X2FwaV9rZXksIOqwkOyCrCDroZzqt7gsIGZpbHRlcl9y"
    "ZXNwb25zZSwgcmF0ZSBsaW1pdC4KIyBBUEkg7YKk64qUIOyEnOuyhCAuZW52IOyXkOunjCDsobTs"
    "nqztlZjrqbAg7J2R64u17JeQIOuFuOy2nOuQmOyngCDslYrripTri6QuCiMg4pWQ4pWQ4pWQ4pWQ"
    "4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ"
    "4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ"
    "4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQCl9I"
    "QU5HVUxfUkUgPSBfcmUuY29tcGlsZShyIltcdWFjMDAtXHVkN2EzXSIpCgpkZWYgX2lzX2tvcmVh"
    "bl9xdWVyeShxKToKICAgIHJldHVybiBib29sKHEgYW5kIF9IQU5HVUxfUkUuc2VhcmNoKHEpKQoK"
    "ZGVmIF9zY2FjaGVfZ2V0KG5hbWUsIHEpOgogICAgaWYgU0VBUkNIX0NBQ0hFX1RUTCA8PSAwOgog"
    "ICAgICAgIHJldHVybiBOb25lCiAgICBlID0gX3NlYXJjaF9jYWNoZS5nZXQoKG5hbWUsIHEpKQog"
    "ICAgaWYgZSBhbmQgKHRpbWUudGltZSgpIC0gZVsxXSkgPCBTRUFSQ0hfQ0FDSEVfVFRMOgogICAg"
    "ICAgIHJldHVybiBlWzBdCiAgICByZXR1cm4gTm9uZQoKZGVmIF9zY2FjaGVfc2V0KG5hbWUsIHEs"
    "IGRhdGEpOgogICAgaWYgU0VBUkNIX0NBQ0hFX1RUTCA+IDA6CiAgICAgICAgX3NlYXJjaF9jYWNo"
    "ZVsobmFtZSwgcSldID0gKGRhdGEsIHRpbWUudGltZSgpKQogICAgICAgIGlmIGxlbihfc2VhcmNo"
    "X2NhY2hlKSA+IDIwMDoKICAgICAgICAgICAgb2xkZXN0ID0gbWluKF9zZWFyY2hfY2FjaGUsIGtl"
    "eT1sYW1iZGEgazogX3NlYXJjaF9jYWNoZVtrXVsxXSkKICAgICAgICAgICAgZGVsIF9zZWFyY2hf"
    "Y2FjaGVbb2xkZXN0XQoKZGVmIF9zdHJpcF90YWdzKHMpOgogICAgcyA9IF9yZS5zdWIociI8W14+"
    "XSs+IiwgIiIsIHMgb3IgIiIpCiAgICByZXR1cm4gKHMucmVwbGFjZSgiJnF1b3Q7IiwgJyInKS5y"
    "ZXBsYWNlKCImYW1wOyIsICImIikKICAgICAgICAgICAgIC5yZXBsYWNlKCImbHQ7IiwgIjwiKS5y"
    "ZXBsYWNlKCImZ3Q7IiwgIj4iKS5yZXBsYWNlKCImbmJzcDsiLCAiICIpKQoKYXN5bmMgZGVmIF9u"
    "YXZlcl9hcGlfc2VhcmNoKHF1ZXJ5LCBraW5kPSJ3ZWJrciIsIGRpc3BsYXk9NSk6CiAgICBpZiBu"
    "b3QgKE5BVkVSX0NMSUVOVF9JRCBhbmQgTkFWRVJfQ0xJRU5UX1NFQ1JFVCk6CiAgICAgICAgcmV0"
    "dXJuIHsib2siOiBGYWxzZSwgImVycm9yIjogIk5BVkVSIGtleXMgbm90IGNvbmZpZ3VyZWQiLCAi"
    "aXRlbXMiOiBbXX0KICAgIGNhY2hlZCA9IF9zY2FjaGVfZ2V0KCJuYXZlcjoiICsga2luZCwgcXVl"
    "cnkpCiAgICBpZiBjYWNoZWQgaXMgbm90IE5vbmU6CiAgICAgICAgcmV0dXJuIGNhY2hlZAogICAg"
    "aW1wb3J0IGh0dHB4CiAgICBlbmRwb2ludCA9IHsKICAgICAgICAid2Via3IiOiAiaHR0cHM6Ly9u"
    "YXZlcmFwaWh1Yi5hcGlndy5udHJ1c3MuY29tL3NlYXJjaC92MS93ZWJrciIsCiAgICAgICAgIm5l"
    "d3MiOiAgImh0dHBzOi8vbmF2ZXJhcGlodWIuYXBpZ3cubnRydXNzLmNvbS9zZWFyY2gvdjEvbmV3"
    "cyIsCiAgICAgICAgImJsb2ciOiAgImh0dHBzOi8vbmF2ZXJhcGlodWIuYXBpZ3cubnRydXNzLmNv"
    "bS9zZWFyY2gvdjEvYmxvZyIsCiAgICAgICAgImVuY3ljIjogImh0dHBzOi8vbmF2ZXJhcGlodWIu"
    "YXBpZ3cubnRydXNzLmNvbS9zZWFyY2gvdjEvZW5jeWMiLAogICAgICAgICJsb2NhbCI6ICJodHRw"
    "czovL25hdmVyYXBpaHViLmFwaWd3Lm50cnVzcy5jb20vc2VhcmNoL3YxL2xvY2FsIiwKICAgIH0u"
    "Z2V0KGtpbmQsICJodHRwczovL25hdmVyYXBpaHViLmFwaWd3Lm50cnVzcy5jb20vc2VhcmNoL3Yx"
    "L3dlYmtyIikKICAgIGhlYWRlcnMgPSB7IlgtTkNQLUFQSUdXLUFQSS1LRVktSUQiOiBOQVZFUl9D"
    "TElFTlRfSUQsCiAgICAgICAgICAgICAgICJYLU5DUC1BUElHVy1BUEktS0VZIjogTkFWRVJfQ0xJ"
    "RU5UX1NFQ1JFVH0KICAgIHBhcmFtcyA9IHsicXVlcnkiOiBxdWVyeSwgImRpc3BsYXkiOiBtYXgo"
    "MSwgbWluKGRpc3BsYXksIDEwKSksICJzdGFydCI6IDEsICJmb3JtYXQiOiAianNvbiJ9CiAgICB0"
    "cnk6CiAgICAgICAgYXN5bmMgd2l0aCBodHRweC5Bc3luY0NsaWVudCh0aW1lb3V0PVNFQVJDSF9U"
    "SU1FT1VUKSBhcyBjOgogICAgICAgICAgICByID0gYXdhaXQgYy5nZXQoZW5kcG9pbnQsIGhlYWRl"
    "cnM9aGVhZGVycywgcGFyYW1zPXBhcmFtcykKICAgICAgICBpZiByLnN0YXR1c19jb2RlICE9IDIw"
    "MDoKICAgICAgICAgICAgcmV0dXJuIHsib2siOiBGYWxzZSwgImVycm9yIjogIm5hdmVyIGh0dHAg"
    "JXMiICUgci5zdGF0dXNfY29kZSwgIml0ZW1zIjogW119CiAgICAgICAgZGF0YSA9IHIuanNvbigp"
    "CiAgICAgICAgaXRlbXMgPSBbeyJ0aXRsZSI6IF9zdHJpcF90YWdzKGl0LmdldCgidGl0bGUiLCAi"
    "IikpLAogICAgICAgICAgICAgICAgICAic25pcHBldCI6IF9zdHJpcF90YWdzKGl0LmdldCgiZGVz"
    "Y3JpcHRpb24iLCAiIikpLAogICAgICAgICAgICAgICAgICAidXJsIjogaXQuZ2V0KCJsaW5rIiwg"
    "IiIpfSBmb3IgaXQgaW4gZGF0YS5nZXQoIml0ZW1zIiwgW10pXQogICAgICAgIG91dCA9IHsib2si"
    "OiBUcnVlLCAic291cmNlIjogIm5hdmVyOiIgKyBraW5kLCAiaXRlbXMiOiBpdGVtc30KICAgICAg"
    "ICBfc2NhY2hlX3NldCgibmF2ZXI6IiArIGtpbmQsIHF1ZXJ5LCBvdXQpCiAgICAgICAgcmV0dXJu"
    "IG91dAogICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgIHJldHVybiB7Im9rIjogRmFs"
    "c2UsICJlcnJvciI6ICJuYXZlcjogJXMiICUgZSwgIml0ZW1zIjogW119CgpkZWYgX2Zvcm1hdF9z"
    "ZWFyY2hfcmVzdWx0cyhyZXMpOgogICAgaWYgbm90IHJlcy5nZXQoIm9rIik6CiAgICAgICAgcmV0"
    "dXJuICLqsoDsg4kg7Iuk7YyoOiAlcyIgJSByZXMuZ2V0KCJlcnJvciIsICLslYwg7IiYIOyXhuuK"
    "lCDsmKTrpZgiKQogICAgbGluZXMgPSBbXQogICAgaWYgcmVzLmdldCgiYW5zd2VyIik6CiAgICAg"
    "ICAgbGluZXMuYXBwZW5kKCLsmpTslb06ICIgKyByZXNbImFuc3dlciJdKTsgbGluZXMuYXBwZW5k"
    "KCIiKQogICAgZm9yIGksIGl0IGluIGVudW1lcmF0ZShyZXMuZ2V0KCJpdGVtcyIsIFtdKSwgMSk6"
    "CiAgICAgICAgdCA9IChpdC5nZXQoInRpdGxlIikgb3IgIiIpLnN0cmlwKCkKICAgICAgICBzbiA9"
    "IChpdC5nZXQoInNuaXBwZXQiKSBvciAiIikuc3RyaXAoKQogICAgICAgIHUgPSAoaXQuZ2V0KCJ1"
    "cmwiKSBvciAiIikuc3RyaXAoKQogICAgICAgIGJsb2NrID0gKCIlZC4gJXMiICUgKGksIHQpKSBp"
    "ZiB0IGVsc2UgKCIlZC4iICUgaSkKICAgICAgICBpZiBzbjoKICAgICAgICAgICAgYmxvY2sgKz0g"
    "IlxuICAgIiArIHNuCiAgICAgICAgaWYgdToKICAgICAgICAgICAgYmxvY2sgKz0gIlxuICAgIiAr"
    "IHUKICAgICAgICBsaW5lcy5hcHBlbmQoYmxvY2spCiAgICByZXR1cm4gIlxuIi5qb2luKGxpbmVz"
    "KSBpZiBsaW5lcyBlbHNlICLqsoDsg4kg6rKw6rO86rCAIOyXhuyKteuLiOuLpC4iCgpjbGFzcyBT"
    "ZWFyY2hSZXF1ZXN0KEJhc2VNb2RlbCk6CiAgICBxdWVyeTogc3RyID0gRmllbGQoLi4uLCBtaW5f"
    "bGVuZ3RoPTEsIG1heF9sZW5ndGg9NTAwKQogICAga2luZDogc3RyID0gRmllbGQoZGVmYXVsdD0i"
    "YXV0byIsIG1heF9sZW5ndGg9MjApCiAgICBkaXNwbGF5OiBpbnQgPSBGaWVsZChkZWZhdWx0PTUs"
    "IGdlPTEsIGxlPTEwKQoKQGFwcC5wb3N0KCIvc2VhcmNoIikKQGxpbWl0ZXIubGltaXQoIjIwL21p"
    "bnV0ZSIpCmFzeW5jIGRlZiBzZWFyY2gocmVxdWVzdDogUmVxdWVzdCwgYm9keTogU2VhcmNoUmVx"
    "dWVzdCwgXz1EZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAgICAiIiLrhKTsnbTrsoQgU2VhcmNo"
    "IEFQSSDsoITsmqkg6rKA7IOJIOyXlOuTnO2PrOyduO2KuC4KICAgIGtpbmTqsIAg7KeA7KCV65CY"
    "66m0IOuEpOydtOuyhCBTZWFyY2ggQVBJ7J2YIO2VtOuLuSDrtoTslbzrpbwg7IKs7Jqp7ZWY6rOg"
    "LAogICAgYXV0by93ZWLsnYAg64Sk7J2067KEIOybueusuOyEnCDqsoDsg4kod2Via3Ip7Jy866Gc"
    "IOyymOumrO2VqeuLiOuLpC4KICAgIOyZuOu2gOydmCDri6Trpbgg6rKA7IOJIEFQSeuhnCDtj7Tr"
    "sLHtlZjsp4Ag7JWK7Iq164uI64ukLgogICAgIiIiCiAgICBxID0gYm9keS5xdWVyeS5zdHJpcCgp"
    "CiAgICBpZiBub3QgcToKICAgICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKDQwMCwgImVtcHR5IHF1"
    "ZXJ5IikKICAgIGNpcCA9IHJlcXVlc3QuY2xpZW50Lmhvc3QgaWYgcmVxdWVzdC5jbGllbnQgZWxz"
    "ZSAiPyIKICAgIGF1ZGl0X2xvZ2dlci5pbmZvKCJTRUFSQ0h8JXN8a2luZD0lc3wlcyIgJSAoY2lw"
    "LCBib2R5LmtpbmQsIHFbOjgwXSkpCgogICAga2luZCA9IGJvZHkua2luZC5sb3dlcigpCiAgICBp"
    "ZiBraW5kIG5vdCBpbiAoImF1dG8iLCAid2ViIiwgIndlYmtyIiwgIm5ld3MiLCAiYmxvZyIsICJl"
    "bmN5YyIsICJsb2NhbCIpOgogICAgICAgIGtpbmQgPSAiYXV0byIKICAgIG5hdmVyX2tpbmQgPSAi"
    "d2Via3IiIGlmIGtpbmQgaW4gKCJhdXRvIiwgIndlYiIpIGVsc2Uga2luZAoKICAgIHJlcyA9IGF3"
    "YWl0IF9uYXZlcl9hcGlfc2VhcmNoKHEsIG5hdmVyX2tpbmQsIGJvZHkuZGlzcGxheSkKICAgIHJv"
    "dXRlZCA9ICJuYXZlcjoiICsgbmF2ZXJfa2luZAogICAgdGV4dCA9IF9mb3JtYXRfc2VhcmNoX3Jl"
    "c3VsdHMocmVzKQogICAgdHJ5OgogICAgICAgIHRleHQgPSBmaWx0ZXJfcmVzcG9uc2UodGV4dCkK"
    "ICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcGFzcwogICAgb2sgPSBib29sKHJlcy5nZXQo"
    "Im9rIikgYW5kIHJlcy5nZXQoIml0ZW1zIikpCiAgICBhdWRpdF9sb2dnZXIuaW5mbygiU0VBUkNI"
    "XyVzfHJvdXRlZD0lc3xpdGVtcz0lZCIgJQogICAgICAgICAgICAgICAgICAgICAgKCJPSyIgaWYg"
    "b2sgZWxzZSAiRU1QVFkiLCByb3V0ZWQsIGxlbihyZXMuZ2V0KCJpdGVtcyIsIFtdKSkpKQogICAg"
    "cmV0dXJuIHsic3VjY2VzcyI6IG9rLCAicm91dGVkIjogcm91dGVkLCAicXVlcnkiOiBxLAogICAg"
    "ICAgICAgICAiYW5zd2VyIjogIiIsICJyZXN1bHRzIjogcmVzLmdldCgiaXRlbXMiLCBbXSksCiAg"
    "ICAgICAgICAgICJzdW1tYXJ5X3BsYWluIjogdGV4dCwgInN1bW1hcnkiOiB0ZXh0LAogICAgICAg"
    "ICAgICAidGltZXN0YW1wIjogZGF0ZXRpbWUubm93KCkuaXNvZm9ybWF0KCl9CgoKaWYgX19uYW1l"
    "X18gPT0gIl9fbWFpbl9fIjoKICAgIGltcG9ydCB1dmljb3JuCiAgICB1dmljb3JuLnJ1bihhcHAs"
    "IGhvc3Q9IjAuMC4wLjAiLCBwb3J0PTgwMDEsCiAgICAgICAgICAgICAgICBzZXJ2ZXJfaGVhZGVy"
    "PUZhbHNlLCAgIyBbU0VDVVJJVFldIOyEnOuyhCDtl6TrjZQg7Iio6rmACiAgICAgICAgICAgICAg"
    "ICBhY2Nlc3NfbG9nPVRydWUpCg=="

)
dest = os.environ.get('AGENT_DIR','') + '/agent_server.py'
with open(dest, 'w', encoding='utf-8') as f:
    f.write(base64.b64decode(b64).decode('utf-8'))
print('  ✅ agent_server.py v6.4.0 생성 완료')
WRITE_AGENT
ok "FILE 4/6  agent_server.py"

############################################
# 4-1. agent_server.py 보안 강화 패치 (7항목)
# ① IP 차단 + 자동 블랙리스트
# ② 요청 서명 검증 (HMAC-SHA256 + Timestamp)
# ③ AI 응답 민감정보 필터링
# ④ Path Traversal 이중 검증
# ⑤ 메모리 입력값 스키마 검증
# ⑥ Docker 리소스 제한 강화 (pids + ulimits)
# ⑦ 감사 로그 JSON 구조화
############################################
step "4-1/9  보안 강화 패치 (7항목)"

AGENT_DIR="${AGENT_DIR}" python3 << 'SEC_PATCH'
import base64, re, os, json

agent_path = os.environ.get('AGENT_DIR', '') + '/agent_server.py'
try:
    with open(agent_path, 'r', encoding='utf-8') as f:
        code = f.read()
except FileNotFoundError:
    print(f"  ❌ 파일 없음: {agent_path}")
    import sys; sys.exit(1)

# ── 패치 ①: IP 차단 + 자동 블랙리스트 ─────────────────────────────
# verify_api_key 전체 교체
OLD_VERIFY = '''def verify_api_key(request: Request):
    auth = request.headers.get("Authorization", "")
    key = _load_api_key()
    if not key: return True
    token = auth.replace("Bearer ", "").strip()
    if not token:
        audit_logger.info(f"AUTH_MISSING|{request.client.host}|{request.url.path}")
        raise HTTPException(status_code=401, detail="Authorization required")
    if not hmac.compare_digest(token.encode(), key.encode()):
        audit_logger.info(f"AUTH_FAIL|{request.client.host}|{request.url.path}")
        raise HTTPException(status_code=403, detail="Invalid API key")
    return True'''

NEW_VERIFY = '''# [SECURITY] IP 차단 블랙리스트 (5회 실패 → 30분 잠금, 재시작 후에도 유지)
import threading as _threading
_ip_lock = _threading.Lock()
_IP_FAIL: dict = {}          # ip → (fail_count, lockout_until | None)
_IP_BL_FILE = "/app/data/ip_blacklist.json"
_IP_MAX_FAIL  = 5
_IP_LOCKOUT_M = 30

def _load_ip_bl():
    try:
        with open(_IP_BL_FILE) as f:
            return {k: v for k, v in json.load(f).items()}
    except Exception:
        return {}

def _save_ip_bl():
    try:
        with open(_IP_BL_FILE, "w") as f:
            json.dump({k: list(v) for k, v in _IP_FAIL.items()}, f)
    except Exception:
        pass

def _ip_blocked(ip: str) -> bool:
    import datetime
    with _ip_lock:
        if ip not in _IP_FAIL:
            return False
        cnt, until = _IP_FAIL[ip]
        if until is None:
            return False
        now = datetime.datetime.utcnow().isoformat()
        if now < until:
            return True
        del _IP_FAIL[ip]
        return False

def _ip_fail(ip: str):
    import datetime
    with _ip_lock:
        cnt = (_IP_FAIL.get(ip, (0, None))[0]) + 1
        if cnt >= _IP_MAX_FAIL:
            until = (datetime.datetime.utcnow() +
                     datetime.timedelta(minutes=_IP_LOCKOUT_M)).isoformat()
            _IP_FAIL[ip] = (cnt, until)
            _save_ip_bl()
            audit_logger.warning(f"IP_LOCKOUT|{ip}|fails={cnt}|until={until}")
        else:
            _IP_FAIL[ip] = (cnt, None)

def _ip_ok(ip: str):
    with _ip_lock:
        _IP_FAIL.pop(ip, None)

# 시작 시 저장된 블랙리스트 로드
try:
    _IP_FAIL.update(_load_ip_bl())
except Exception:
    pass

def verify_api_key(request: Request):
    ip  = request.client.host if request.client else "unknown"
    # IP 잠금 확인
    if _ip_blocked(ip):
        audit_logger.warning(f"IP_BLOCKED|{ip}|{request.url.path}")
        raise HTTPException(status_code=429, detail="Too many failed attempts — try again later")
    auth = request.headers.get("Authorization", "")
    key  = _load_api_key()
    if not key: return True
    token = auth.replace("Bearer ", "").strip()
    if not token:
        _ip_fail(ip)
        audit_logger.info(f"AUTH_MISSING|{ip}|{request.url.path}")
        raise HTTPException(status_code=401, detail="Authorization required")
    if not hmac.compare_digest(token.encode(), key.encode()):
        _ip_fail(ip)
        audit_logger.info(f"AUTH_FAIL|{ip}|{request.url.path}")
        raise HTTPException(status_code=403, detail="Invalid API key")
    _ip_ok(ip)  # 성공 시 카운터 초기화
    return True'''

if OLD_VERIFY in code:
    code = code.replace(OLD_VERIFY, NEW_VERIFY)
    print("  ✅ 패치 ①: IP 차단 + 자동 블랙리스트")
else:
    print("  ⚠️  패치 ①: verify_api_key 위치 불일치")

# ── 패치 ②: 요청 서명 검증 (HMAC-SHA256 + 5분 타임스탬프 윈도우) ──
# security_headers 미들웨어 안에 타임스탬프 검증 추가
OLD_BODY_LIMIT = '''    # [SECURITY] 요청 본문 크기 제한 (10KB)
    content_length = request.headers.get("content-length", "0")
    if int(content_length) > 10240:'''

NEW_BODY_LIMIT = '''    # [SECURITY] 요청 본문 크기 제한 (10KB)
    content_length = request.headers.get("content-length", "0")
    if int(content_length) > 10240:'''  # 이 패치는 별도 위치에 삽입

# verify_api_key 이후 별도 서명 검증 함수 추가
OLD_VALIDATE_URL = '''# [SECURITY] URL 검증
def validate_url(url: str) -> bool:'''

NEW_VALIDATE_URL = '''# [SECURITY] ② 요청 서명 검증 (X-Timestamp + X-Signature)
# 선택적 강화 — ENABLE_REQUEST_SIGNING=true 시 활성화
_SIGN_ENABLED = os.getenv("ENABLE_REQUEST_SIGNING", "false").lower() == "true"
_SIGN_WINDOW  = int(os.getenv("REQUEST_SIGN_WINDOW", "300"))  # 5분

async def verify_request_signature(request: Request):
    """HMAC-SHA256 서명 + 타임스탬프 + 본문해시로 Replay Attack 및 요청 위조 방지"""
    if not _SIGN_ENABLED:
        return  # 비활성화 시 건너뜀
    import time as _time
    ts  = request.headers.get("X-Timestamp", "")
    sig = request.headers.get("X-Signature", "")
    if not ts or not sig:
        raise HTTPException(status_code=400, detail="Missing X-Timestamp or X-Signature")
    try:
        req_time = int(ts)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid X-Timestamp")
    # 타임스탬프 윈도우 (±5분)
    if abs(_time.time() - req_time) > _SIGN_WINDOW:
        audit_logger.warning(f"SIGN_REPLAY|ts={ts}|path={request.url.path}")
        raise HTTPException(status_code=400, detail="Request expired or clock skew too large")
    # [FIX H2] 본문 해시를 서명에 포함 — 윈도우 내 본문 재사용(바꿔치기) 방지
    raw_body = await request.body()
    body_hash = hashlib.sha256(raw_body).hexdigest()
    # HMAC-SHA256 검증 (ts:method:path:body_hash)
    key  = _load_api_key().encode()
    body = f"{ts}:{request.method}:{request.url.path}:{body_hash}".encode()
    expected = hmac.new(key, body, digestmod=hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig, expected):
        audit_logger.warning(f"SIGN_FAIL|{request.client.host}|{request.url.path}")
        raise HTTPException(status_code=403, detail="Invalid request signature")

# [SECURITY] URL 검증
def validate_url(url: str) -> bool:'''

if OLD_VALIDATE_URL in code:
    code = code.replace(OLD_VALIDATE_URL, NEW_VALIDATE_URL)
    print("  ✅ 패치 ②: 요청 서명 검증 (HMAC-SHA256 + Timestamp)")
else:
    print("  ⚠️  패치 ②: validate_url 위치 불일치")

# ── 패치 ③: AI 응답 민감정보 필터링 ─────────────────────────────
OLD_SANITIZE_END = '''    task_lower = task.lower()
    for p in injection_patterns:
        if p in task_lower:
            audit_logger.info(f"INJECTION_ATTEMPT|{p}|{task[:100]}")
            break
    return task.strip()'''

NEW_SANITIZE_END = '''    task_lower = task.lower()
    for p in injection_patterns:
        if p in task_lower:
            audit_logger.info(f"INJECTION_ATTEMPT|{p}|{task[:100]}")
            # [SECURITY] 로그만 남기지 않고 인젝션 문구를 실제로 무력화
            task = _re.sub(_re.escape(p), "[BLOCKED]", task, flags=_re.IGNORECASE)
    return task.strip()[:2000]

# [SECURITY] ③ AI 응답 민감정보 자동 필터링
_RESP_FILTERS = [
    (_re.compile(r'(sk-[a-zA-Z0-9]{4})[a-zA-Z0-9]{16,}'),                r'\\1[REDACTED]'),
    (_re.compile(r'(eyJ[a-zA-Z0-9_-]{8,})\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'), r'\\1.[REDACTED]'),
    (_re.compile(r'(?i)(api[_\\s\\-]?key[\\s:="\\\']+)([a-zA-Z0-9_\\-]{20,})'), r'\\1[REDACTED]'),
    (_re.compile(r'(?i)(password[\\s:="\\\']+)(\\S{6,})'),                r'\\1[REDACTED]'),
    (_re.compile(r'(\\+82\\d{2})\\d{4}(\\d{4})'),                         r'\\1****\\2'),
    (_re.compile(r'\\b(010|011|016|017|018|019)-?\\d{4}-(\\d{4})\\b'),     r'\\1-****-\\2'),
    (_re.compile(r'(?i)(secret[\\s:="\\\']+)([a-zA-Z0-9_\\-]{8,})'),      r'\\1[REDACTED]'),
]

def filter_response(text: str) -> str:
    """AI 응답에서 민감정보 자동 마스킹"""
    if not text:
        return text
    for pat, repl in _RESP_FILTERS:
        text = pat.sub(repl, text)
    return text'''

if OLD_SANITIZE_END in code:
    code = code.replace(OLD_SANITIZE_END, NEW_SANITIZE_END)
    print("  ✅ 패치 ③: AI 응답 민감정보 필터링")
else:
    print("  ⚠️  패치 ③: sanitize_task 끝부분 위치 불일치")

# [FALLBACK] filter_response 정의 보장 — 앵커 불일치로 패치 ③이 실패해도
# filter_response 호출부(③-b 등)는 삽입되므로, 정의가 없으면 NameError 발생.
# 정의가 코드에 없으면 import 블록 직후에 강제로 주입한다.
if "def filter_response" not in code:
    _FILTER_DEF = '''
# [SECURITY] ③ AI 응답 민감정보 자동 필터링 (fallback 주입)
_RESP_FILTERS = [
    (_re.compile(r'(sk-[a-zA-Z0-9]{4})[a-zA-Z0-9]{16,}'),                r'\\1[REDACTED]'),
    (_re.compile(r'(eyJ[a-zA-Z0-9_-]{8,})\\.[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+'), r'\\1.[REDACTED]'),
    (_re.compile(r'(?i)(api[_\\s\\-]?key[\\s:="\\\']+)([a-zA-Z0-9_\\-]{20,})'), r'\\1[REDACTED]'),
    (_re.compile(r'(?i)(password[\\s:="\\\']+)(\\S{6,})'),                r'\\1[REDACTED]'),
    (_re.compile(r'(\\+82\\d{2})\\d{4}(\\d{4})'),                         r'\\1****\\2'),
    (_re.compile(r'\\b(010|011|016|017|018|019)-?\\d{4}-(\\d{4})\\b'),     r'\\1-****-\\2'),
    (_re.compile(r'(?i)(secret[\\s:="\\\']+)([a-zA-Z0-9_\\-]{8,})'),      r'\\1[REDACTED]'),
]

def filter_response(text: str) -> str:
    """AI 응답에서 민감정보 자동 마스킹"""
    if not text:
        return text
    for pat, repl in _RESP_FILTERS:
        text = pat.sub(repl, text)
    return text

'''
    # import 블록 직후(마지막 import 줄 다음)에 주입
    _lines = code.splitlines(keepends=True)
    _last_import = 0
    for _i, _ln in enumerate(_lines):
        _s = _ln.lstrip()
        if _s.startswith("import ") or _s.startswith("from "):
            _last_import = _i
    _lines.insert(_last_import + 1, _FILTER_DEF)
    code = "".join(_lines)
    print("  ✅ 패치 ③-fallback: filter_response 정의 강제 주입 (import 블록 직후)")
else:
    print("  ℹ️  filter_response 정의 이미 존재 — fallback 불필요")

# ── 패치 ④: Path Traversal 이중 검증 강화 ────────────────────────
OLD_PATH = '''        raise ValueError("Path traversal blocked")'''

NEW_PATH = '''        raise ValueError("Path traversal blocked (relative path)")
    # Null byte 삽입 방어
    if "\\x00" in filename or "%00" in filename:
        audit_logger.warning(f"PATH_NULL_BYTE|{filename[:80]}")
        raise ValueError("Path traversal blocked (null byte)")
    # realpath 검증 (심볼릭 링크 우회 방어)
    import pathlib as _pathlib
    try:
        resolved = str(_pathlib.Path(USER_FILES_DIR / filename).resolve())
        if not resolved.startswith(str(_pathlib.Path(USER_FILES_DIR).resolve())):
            audit_logger.warning(f"PATH_ESCAPE|{filename[:80]}")
            raise ValueError("Path traversal blocked (escape attempt)")
    except Exception as pe:
        raise ValueError(f"Path traversal blocked: {pe}")'''

if OLD_PATH in code:
    code = code.replace(OLD_PATH, NEW_PATH, 1)
    print("  ✅ 패치 ④: Path Traversal 이중 검증 (null byte + realpath)")
else:
    print("  ⚠️  패치 ④: Path traversal 위치 불일치")

# ── 패치 ⑤: 메모리 입력값 스키마 검증 ─────────────────────────────
# 데코레이터(@app.post)와 함수 정의 사이에 삽입되지 않도록
# 데코레이터까지 포함한 전체 패턴을 앵커로 사용
OLD_MEMORY = '''@app.post("/memory")
async def update_memory(request: Request, _=Depends(verify_api_key)):'''

NEW_MEMORY = '''# [SECURITY] ⑤ 메모리 허용 키 화이트리스트 + 값 타입·길이 제한
_MEMORY_SCHEMA = {
    "location":       (str,  200),
    "interests":      (list, 20),
    "preferences":    (dict, 10),
    "name":           (str,  100),
    "language":       (str,  20),
    "occupation":     (str,  100),
    "notes":          (str,  500),
    "search_history": (list, 50),
    "facts":          (list, 30),
    "past_queries":   (list, 50),
}
_MEMORY_MAX_KEYS = 20

def validate_memory_update(body):
    """메모리 업데이트 입력값 검증 — 허용 키만, 타입·길이 제한"""
    if len(body) > _MEMORY_MAX_KEYS:
        raise HTTPException(400, f"Too many keys (max {_MEMORY_MAX_KEYS})")
    cleaned = {}
    for k, v in body.items():
        if not _re.match(r'^[a-zA-Z_][a-zA-Z0-9_]{0,49}$', k):
            audit_logger.warning(f"MEMORY_INVALID_KEY|{k[:30]}")
            continue
        if k in _MEMORY_SCHEMA:
            expected_type, max_len = _MEMORY_SCHEMA[k]
            if not isinstance(v, expected_type):
                raise HTTPException(400, f"Invalid type for key '{k}'")
            if isinstance(v, str) and len(v) > max_len:
                v = v[:max_len]
            if isinstance(v, (list, dict)) and len(v) > max_len:
                raise HTTPException(400, f"Value too large for key '{k}'")
        elif isinstance(v, str):
            v = v[:200]
        cleaned[k] = v
    return cleaned

@app.post("/memory")
async def update_memory(request: Request, _=Depends(verify_api_key)):'''

if OLD_MEMORY in code:
    code = code.replace(OLD_MEMORY, NEW_MEMORY)
    print("  ✅ 패치 ⑤: 메모리 입력값 스키마 검증")
else:
    print("  ⚠️  패치 ⑤: update_memory 위치 불일치")

# ── 패치 ⑦: 감사 로그 JSON 구조화 ───────────────────────────────
OLD_AUDIT_SETUP = '''audit_logger = logging.getLogger("audit")
_ah = logging.FileHandler("/app/data/audit/agent.log")
_ah.setFormatter(logging.Formatter("%(asctime)s|%(message)s"))
audit_logger.addHandler(_ah)
audit_logger.setLevel(logging.INFO)'''

NEW_AUDIT_SETUP = '''import logging.handlers  # RotatingFileHandler 서브모듈 명시 import
audit_logger = logging.getLogger("audit")
_ah = logging.handlers.RotatingFileHandler(
    "/app/data/audit/agent.log",
    maxBytes=10 * 1024 * 1024,  # 10MB
    backupCount=3, encoding="utf-8"
)
_ah.setFormatter(logging.Formatter("%(message)s"))  # JSON 단독 출력
audit_logger.addHandler(_ah)
audit_logger.setLevel(logging.INFO)
audit_logger.propagate = False  # 메인 로거로 전파 차단

def _audit(event: str, ip: str = "", detail: str = "", ok: bool = True, **extra):
    """JSON 구조화 감사 로그"""
    import datetime as _dt
    rec = {"ts": _dt.datetime.utcnow().isoformat(timespec="seconds") + "Z",
           "event": event, "ip": ip, "ok": ok}
    if detail: rec["detail"] = detail[:200]
    rec.update(extra)
    audit_logger.info(json.dumps(rec, ensure_ascii=False))'''

if OLD_AUDIT_SETUP in code:
    code = code.replace(OLD_AUDIT_SETUP, NEW_AUDIT_SETUP)
    print("  ✅ 패치 ⑦: 감사 로그 JSON 구조화 + RotatingFileHandler")
else:
    # 대체 패턴 시도
    ALT = '''audit_logger = logging.getLogger("audit")
_ah = logging.FileHandler("/app/data/audit/agent.log")'''
    if ALT in code:
        code = code.replace(ALT,
            'import logging.handlers as _lh\naudit_logger = logging.getLogger("audit")\n'
            '_ah = _lh.RotatingFileHandler("/app/data/audit/agent.log", maxBytes=10*1024*1024, backupCount=3, encoding="utf-8")')
        print("  ✅ 패치 ⑦ (대체 패턴): RotatingFileHandler 적용")
    else:
        print("  ⚠️  패치 ⑦: audit_logger 위치 불일치")

# ── filter_response 호출 삽입 (BROWSE_OK, MULTI_OK 직전) ─────────
# browse 엔드포인트 결과에 필터 적용
OLD_BROWSE_OK = '''            audit_logger.info(f"BROWSE_OK|steps={result['steps_taken']}|{result['elapsed_sec']}s")'''
NEW_BROWSE_OK = '''            result["summary"] = filter_response(result.get("summary", ""))
            audit_logger.info(f"BROWSE_OK|steps={result['steps_taken']}|{result['elapsed_sec']}s")'''
if OLD_BROWSE_OK in code:
    code = code.replace(OLD_BROWSE_OK, NEW_BROWSE_OK)
    print("  ✅ 패치 ③-b: browse 응답에 필터 적용")

# ── update_memory 내부에서 validate_memory_update 호출 삽입 ──────
OLD_MEM_BODY = '''    body = await request.json()
    mem = _load_memory()
    if "location" in body: mem["location"] = str(body["location"])[:50]'''
NEW_MEM_BODY = '''    body = await request.json()
    body = validate_memory_update(body)  # [SECURITY] 스키마 검증
    mem = _load_memory()
    if "location" in body: mem["location"] = str(body["location"])[:50]'''
if OLD_MEM_BODY in code:
    code = code.replace(OLD_MEM_BODY, NEW_MEM_BODY)
    print("  ✅ 패치 ⑤-b: update_memory에 스키마 검증 연결")
else:
    print("  ⚠️  패치 ⑤-b: update_memory 본문 위치 불일치")

# 최종 저장
with open(agent_path, 'w', encoding='utf-8') as f:
    f.write(code)

print(f"\n  📋 agent_server.py 최종 라인 수: {len(code.splitlines())}")
print("  ✅ 보안 패치 완료!")
SEC_PATCH

ok "보안 패치 완료 (agent_server.py)"

############################################
# 4-2. agent_server.py 기능 업그레이드 (12항목)
# ① 스크린샷  ② 히스토리  ③ 취소  ④ SSE 스트리밍
# ⑤ 배치처리  ⑥ 세션저장  ⑦ 브라우저풀  ⑧ 프록시
# ⑨ 모니터링 (서버측)
############################################
step "4-2/9  기능 업그레이드 — server 9항목"

AGENT_DIR="${AGENT_DIR}" python3 << 'UPGRADE_PATCH'
import os, re, sys, json

agent_path = os.environ.get('AGENT_DIR','') + '/agent_server.py'
try:
    with open(agent_path, encoding='utf-8') as f: code = f.read()
except FileNotFoundError:
    print(f"  ❌ 파일 없음: {agent_path}"); sys.exit(1)

ok_list = []

# 임포트 보강
OLD_IMP = 'import asyncio, os, json, time, logging, hashlib, hmac, secrets, re as _re'
if OLD_IMP in code:
    code = code.replace(OLD_IMP,
        OLD_IMP + '\nimport uuid as _uuid, csv as _csv, collections as _collections\n'
        'from pathlib import Path as _Path')
    ok_list.append('임포트')

# 설정 변수 (MAX_CONCURRENT 이후 삽입)
OLD_MAX = 'MAX_CONCURRENT = int(os.getenv("MAX_CONCURRENT", "3"))'
EXTRA = '''
_task_history: _collections.deque = _collections.deque(maxlen=100)
_cancel_events: dict = {}
BROWSER_POOL_SIZE = int(os.getenv("BROWSER_POOL_SIZE", "0"))
BROWSER_PROXY     = os.getenv("BROWSER_PROXY", "")
_MONITORS_FILE    = "/app/data/monitors.json"
_monitors: dict   = {}
def _init_monitors():
    global _monitors
    try:
        with open(_MONITORS_FILE) as f: _monitors = json.load(f)
    except Exception: _monitors = {}
def _save_monitors():
    try:
        with open(_MONITORS_FILE, "w") as f:
            json.dump(_monitors, f, ensure_ascii=False, indent=2)
    except Exception: pass
'''
if OLD_MAX in code:
    code = code.replace(OLD_MAX, OLD_MAX + EXTRA)
    ok_list.append('설정 변수')

# lifespan 초기화
OLD_LF = 'logger.info(f"Concurrency limit: {MAX_CONCURRENT}")'
if OLD_LF in code:
    code = code.replace(OLD_LF,
        OLD_LF + '\n    _init_monitors()\n    asyncio.create_task(_monitor_loop())')
    ok_list.append('lifespan')

# 프록시: browse 첫 번째 headless 에 적용
OLD_HL = 'headless=True, disable_security=False,'
if OLD_HL in code:
    code = code.replace(OLD_HL,
        OLD_HL + '\n            proxy={"server": BROWSER_PROXY} if BROWSER_PROXY else None,', 1)
    ok_list.append('프록시')

# 히스토리: browse 성공 시 저장
OLD_BOK = "audit_logger.info(f\"BROWSE_OK|steps={result['steps_taken']}|{result['elapsed_sec']}s\")"
if OLD_BOK in code:
    code = code.replace(OLD_BOK,
        "_task_history.appendleft({'id':secrets.token_hex(4),'task':raw_task[:100],"
        "'status':'ok','steps':result.get('steps_taken',0),"
        "'elapsed':result.get('elapsed_sec',0),'ts':time.strftime('%Y-%m-%dT%H:%M:%S')})\n"
        "            " + OLD_BOK)
    ok_list.append('히스토리')

# 새 엔드포인트 블록
NEW_EPS = r"""

# ═══ UPGRADE: 추가 엔드포인트 ═══════════════════════════════

# ① 스크린샷
class _ShotReq(BaseModel):
    url: str = Field(..., max_length=500)
    full_page: bool = False
    @field_validator("url")
    @classmethod
    def _c(cls, v):
        if not validate_url(v): raise ValueError("URL not allowed")
        return v

@app.post("/screenshot")
@limiter.limit("10/minute")
async def screenshot(request: Request, body: _ShotReq, _=Depends(verify_api_key)):
    import base64 as _b64
    from playwright.async_api import async_playwright
    try:
        async with async_playwright() as pw:
            proxy_cfg = {"server": BROWSER_PROXY} if BROWSER_PROXY else None
            br  = await pw.chromium.launch(headless=True, proxy=proxy_cfg)
            ctx = await br.new_context(viewport={"width":1280,"height":900})
            pg  = await ctx.new_page()
            await asyncio.wait_for(pg.goto(body.url, wait_until="networkidle"), timeout=30)
            shot = await pg.screenshot(full_page=body.full_page, type="jpeg", quality=75)
            await br.close()
        _audit("SCREENSHOT", detail=body.url[:80])
        return {"screenshot_b64": _b64.b64encode(shot).decode(),
                "url": body.url, "mime": "image/jpeg", "size_bytes": len(shot)}
    except asyncio.TimeoutError: raise HTTPException(504, "Screenshot timed out")
    except Exception as e: raise HTTPException(500, f"Screenshot failed: {e}")

# ② 히스토리
@app.get("/history")
@limiter.limit("30/minute")
async def get_history(request: Request, limit: int = 20, _=Depends(verify_api_key)):
    return {"history": list(_task_history)[:min(limit,100)], "total": len(_task_history)}

@app.delete("/history")
async def clear_history(_=Depends(verify_api_key)):
    _task_history.clear(); return {"cleared": True}

# ③ 취소
@app.post("/tasks/{task_id}/cancel")
async def cancel_task(task_id: str, _=Depends(verify_api_key)):
    if task_id not in _cancel_events:
        raise HTTPException(404, f"Task '{task_id}' not found")
    _cancel_events[task_id].set()
    _audit("TASK_CANCEL", detail=task_id)
    return {"cancelled": True, "task_id": task_id}

@app.get("/tasks")
async def list_tasks(_=Depends(verify_api_key)):
    return {"active": list(_cancel_events.keys()), "count": len(_cancel_events)}

# ④ SSE 스트리밍
try:
    from sse_starlette.sse import EventSourceResponse as _SSE; _SSE_OK = True
except ImportError:
    _SSE_OK = False

class _StReq(BaseModel):
    task: str = Field(..., min_length=1, max_length=2000)
    url:  str = Field(default="", max_length=500)
    max_steps: int = Field(default=15, ge=1, le=30)
    @field_validator("task")
    @classmethod
    def _c(cls, v): return sanitize_task(v)

@app.post("/browse/stream")
@limiter.limit("5/minute")
async def browse_stream(request: Request, body: _StReq, _=Depends(verify_api_key)):
    if not _SSE_OK: raise HTTPException(501, "sse-starlette not installed")
    tid = secrets.token_hex(6)
    _cancel_events[tid] = asyncio.Event()
    async def gen():
        try:
            yield {"data": json.dumps({"type":"start","task_id":tid,"task":body.task[:60]})}
            llm = create_llm()
            if not llm:
                yield {"data": json.dumps({"type":"error","msg":"LLM not configured"})}; return
            from browser_use import Agent
            from browser_use import BrowserSession; from browser_use.browser import BrowserProfile
            proxy_cfg = BrowserProfile(headless=True,
                proxy={"server": BROWSER_PROXY} if BROWSER_PROXY else None)
            task_str = (f"URL: {body.url}\n" if body.url else "") + body.task
            async def _run():
                s = None
                try:
                    s = BrowserSession(browser_profile=proxy_cfg)
                    ag = Agent(task=task_str, llm=llm, browser_session=s, use_vision=False, max_actions_per_step=5)
                    return await asyncio.wait_for(ag.run(max_steps=body.max_steps), timeout=TASK_TIMEOUT)
                finally:
                    if s:
                        try: await asyncio.wait_for(s.close(), timeout=5)
                        except Exception: pass
            worker = asyncio.create_task(_run()); step_n = 0
            while not worker.done():
                if _cancel_events[tid].is_set():
                    worker.cancel()
                    yield {"data": json.dumps({"type":"cancelled","task_id":tid})}; return
                step_n += 1
                yield {"data": json.dumps({"type":"progress","step":step_n,"msg":f"처리 중 (단계 {step_n})"})}
                await asyncio.sleep(2)
            r = worker.result() if not worker.cancelled() else None
            if r:
                s = filter_response(r.final_result() or "")
                yield {"data": json.dumps({"type":"done","task_id":tid,"summary":s[:800],"steps":step_n})}
                _task_history.appendleft({"id":tid,"task":body.task[:80],"status":"ok",
                    "steps":step_n,"ts":time.strftime("%Y-%m-%dT%H:%M:%S")})
            else:
                yield {"data": json.dumps({"type":"error","msg":"failed or cancelled"})}
        except Exception as e:
            yield {"data": json.dumps({"type":"error","msg":str(e)[:200]})}
        finally: _cancel_events.pop(tid, None)
    return _SSE(gen())

# ⑤ 배치 처리
class _BI(BaseModel):
    task: str = Field(..., min_length=1, max_length=2000)
    url:  str = Field(default="", max_length=500)
    @field_validator("task")
    @classmethod
    def _c(cls, v): return sanitize_task(v)

class _BRq(BaseModel):
    tasks: list[_BI] = Field(..., min_length=1, max_length=10)
    parallel: bool = False

@app.post("/browse/batch")
@limiter.limit("2/minute")
async def browse_batch(request: Request, body: _BRq, _=Depends(verify_api_key)):
    async def _one(item: _BI):
        llm = create_llm()
        if not llm: return {"task":item.task[:60],"error":"no LLM","ok":False}
        from browser_use import Agent
        from browser_use import BrowserSession; from browser_use.browser import BrowserProfile
        proxy_cfg = BrowserProfile(headless=True, proxy={"server": BROWSER_PROXY} if BROWSER_PROXY else None)
        task_str = (f"URL: {item.url}\n" if item.url else "") + item.task
        try:
            s  = BrowserSession(browser_profile=proxy_cfg)
            ag = Agent(task=task_str, llm=llm, browser_session=s, use_vision=False, max_actions_per_step=5)
            r  = await asyncio.wait_for(ag.run(max_steps=10), timeout=TASK_TIMEOUT)
            await asyncio.wait_for(s.close(), timeout=5)
            return {"task":item.task[:60],"summary":filter_response(r.final_result() or "")[:400],"ok":True}
        except Exception as e: return {"task":item.task[:60],"error":str(e)[:150],"ok":False}
    if body.parallel:
        results = list(await asyncio.gather(*[_one(i) for i in body.tasks]))
    else:
        results = [await _one(i) for i in body.tasks]
    _audit("BATCH", detail=f"n={len(results)}")
    return {"results": results, "total": len(results), "success": sum(1 for r in results if r.get("ok"))}

# ⑥ 세션 저장/불러오기
_SD = _Path("/app/data/sessions"); _SD.mkdir(parents=True, exist_ok=True)
def _vsn(n): return bool(_re.match(r'^[a-zA-Z0-9_-]{1,32}$', n))

@app.post("/sessions/{name}/save")
@limiter.limit("5/minute")
async def save_session(request: Request, name: str, _=Depends(verify_api_key)):
    if not _vsn(name): raise HTTPException(400, "Invalid name")
    b = await request.json()
    d = {"cookies": b.get("cookies",[]), "localStorage": b.get("localStorage",{}),
         "saved_at": time.strftime("%Y-%m-%dT%H:%M:%S"), "name": name}
    sp = _SD / f"{name}.json"
    with open(sp, "w", encoding="utf-8") as f: json.dump(d, f, ensure_ascii=False, indent=2)
    os.chmod(sp, 0o600)
    _audit("SESSION_SAVE", detail=name)
    return {"saved": True, "name": name, "cookie_count": len(d["cookies"])}

@app.get("/sessions/{name}")
async def load_session(name: str, _=Depends(verify_api_key)):
    if not _vsn(name): raise HTTPException(400, "Invalid name")
    sp = _SD / f"{name}.json"
    if not sp.exists(): raise HTTPException(404, f"Session not found")
    with open(sp, encoding="utf-8") as f: d = json.load(f)
    _audit("SESSION_LOAD", detail=name); return d

@app.get("/sessions")
async def list_sessions(_=Depends(verify_api_key)):
    out = []
    for fp in _SD.glob("*.json"):
        try:
            with open(fp) as f: d = json.load(f)
            out.append({"name":d.get("name",fp.stem),"saved_at":d.get("saved_at",""),"cookie_count":len(d.get("cookies",[]))})
        except Exception: pass
    return {"sessions": out, "count": len(out)}

@app.delete("/sessions/{name}")
async def delete_session(name: str, _=Depends(verify_api_key)):
    if not _vsn(name): raise HTTPException(400, "Invalid name")
    sp = _SD / f"{name}.json"
    if not sp.exists(): raise HTTPException(404, "Session not found")
    sp.unlink(); _audit("SESSION_DEL", detail=name); return {"deleted": True}

# ⑦ 브라우저 풀
class _BPool:
    def __init__(self, sz=2):
        self._q = asyncio.Queue(sz); self._sz = sz; self._ready = False
    async def warm_up(self):
        try:
            from playwright.async_api import async_playwright
            for _ in range(self._sz):
                pw = await async_playwright().__aenter__()
                br = await pw.chromium.launch(headless=True, proxy={"server":BROWSER_PROXY} if BROWSER_PROXY else None)
                await self._q.put((pw, br))
            self._ready = True; logger.info(f"🏊 브라우저 풀 {self._sz}개 준비")
        except Exception as e: logger.warning(f"브라우저 풀 실패: {e}")
    async def acquire(self):
        if not self._ready or self._q.empty(): return None, None
        try: return await asyncio.wait_for(self._q.get(), timeout=2.0)
        except asyncio.TimeoutError: return None, None
    async def release(self, pw, br):
        try:
            if br and not self._q.full(): await self._q.put((pw, br))
            elif br: await br.close()
        except Exception: pass

_browser_pool = _BPool(BROWSER_POOL_SIZE) if BROWSER_POOL_SIZE > 0 else None

@app.get("/pool/status")
async def pool_status(_=Depends(verify_api_key)):
    if not _browser_pool: return {"pool_enabled":False,"note":"BROWSER_POOL_SIZE=0 (비활성)"}
    return {"pool_enabled":True,"size":_browser_pool._sz,"ready":_browser_pool._ready,"available":_browser_pool._q.qsize()}

# ⑧ 프록시 상태
@app.get("/proxy/status")
async def proxy_status(_=Depends(verify_api_key)):
    return {"proxy_enabled":bool(BROWSER_PROXY),"proxy_server":BROWSER_PROXY or None,
            "note":"BROWSER_PROXY=http://user:pass@host:port 으로 설정"}

# ⑨ 모니터링
class _MReq(BaseModel):
    url: str = Field(..., max_length=500)
    keyword: str = Field(..., max_length=200)
    target_value: str = Field(default="", max_length=100)
    label: str = Field(default="", max_length=50)
    interval_minutes: int = Field(default=60, ge=5, le=1440)
    sms_to: str = Field(default="", max_length=30)
    @field_validator("url")
    @classmethod
    def _c(cls, v):
        if not validate_url(v): raise ValueError("URL not allowed")
        return v

@app.post("/monitors")
@limiter.limit("10/minute")
async def add_monitor(request: Request, body: _MReq, _=Depends(verify_api_key)):
    mid = f"mon_{secrets.token_hex(4)}"
    _monitors[mid] = {"id":mid,"url":body.url,"keyword":body.keyword,
        "target_value":body.target_value,"label":body.label or body.keyword[:20],
        "interval_minutes":body.interval_minutes,"created_at":time.strftime("%Y-%m-%dT%H:%M:%S"),
        "sms_to":(body.sms_to or "").strip(),
        "last_checked":None,"last_value":None,"triggered":False}
    _save_monitors(); _audit("MONITOR_ADD", detail=f"{mid}|{body.url[:50]}")
    return {"id":mid,"label":_monitors[mid]["label"]}

@app.get("/monitors")
async def list_monitors(_=Depends(verify_api_key)):
    return {"monitors": list(_monitors.values()), "count": len(_monitors)}

@app.delete("/monitors/{mid}")
async def delete_monitor(mid: str, _=Depends(verify_api_key)):
    if mid not in _monitors: raise HTTPException(404, "Not found")
    del _monitors[mid]; _save_monitors(); return {"deleted":True,"id":mid}

@app.post("/monitors/{mid}/check")
@limiter.limit("5/minute")
async def check_monitor_now(request: Request, mid: str, _=Depends(verify_api_key)):
    if mid not in _monitors: raise HTTPException(404, "Not found")
    mon = _monitors[mid]; llm = create_llm()
    if not llm: raise HTTPException(500, "LLM not configured")
    from browser_use import Agent
    from browser_use import BrowserSession; from browser_use.browser import BrowserProfile
    proxy_cfg = BrowserProfile(headless=True, proxy={"server":BROWSER_PROXY} if BROWSER_PROXY else None)
    task = f"URL: {mon['url']}\n{mon['keyword']} 현재값을 알려줘."
    if mon.get("target_value"): task += f" 목표: '{mon['target_value']}'과 비교."
    try:
        s = BrowserSession(browser_profile=proxy_cfg)
        ag = Agent(task=task, llm=llm, browser_session=s, use_vision=False, max_actions_per_step=5)
        r  = await asyncio.wait_for(ag.run(max_steps=8), timeout=60)
        await asyncio.wait_for(s.close(), timeout=5)
        cv = filter_response(r.final_result() or "")
    except Exception as e: cv = f"오류: {e}"
    mon.update({"last_checked":time.strftime("%Y-%m-%dT%H:%M:%S"),"last_value":cv[:200]})
    triggered = bool(mon.get("target_value") and mon["target_value"] in cv)
    if triggered: mon["triggered"] = True
    _save_monitors(); _audit("MONITOR_CHECK", detail=f"{mid}|triggered={triggered}")
    return {"id":mid,"current_value":cv[:400],"triggered":triggered,"checked_at":mon["last_checked"]}

# [SMS] 모니터 트리거 시 openapi-tools(/tools/send-sms) 경유로 Twilio SMS 발송.
# SMS_NOTIFY_TO 가 비어 있으면 조용히 건너뜀(기능 비활성화). 실패해도 루프는 계속.
SMS_NOTIFY_URL = os.getenv("SMS_NOTIFY_URL", "http://openapi-tools:8000/tools/send-sms")
SMS_NOTIFY_TO  = os.getenv("SMS_NOTIFY_TO", "").strip()
SMS_MAX_RECIPIENTS = int(os.getenv("SMS_MAX_RECIPIENTS", "5"))   # 1회 발송 인원 상한
SMS_ALLOWLIST      = os.getenv("SMS_ALLOWLIST", "").strip()      # 허용 번호(쉼표). 비우면 제한 없음
SMS_HOURLY_CAP     = int(os.getenv("SMS_HOURLY_CAP", "50"))      # 시간당 총 발송 상한(요금 방어)

def _sms_mask(num):
    # 로그 노출 방지: 뒤 4자리만 표시 (+8210****2023)
    n = str(num or "")
    return (n[:3] + "*" * max(0, len(n) - 7) + n[-4:]) if len(n) > 7 else "***"

def _sms_valid(num):
    # E.164 형식만 허용: '+' + 숫자 8~15자리
    import re as _re
    return bool(_re.fullmatch(r"\+[1-9][0-9]{7,14}", num or ""))

def _sms_allowed(num):
    if not SMS_ALLOWLIST:
        return True
    allow = {x.strip() for x in SMS_ALLOWLIST.replace(";", ",").split(",") if x.strip()}
    return num in allow

# 시간당 발송 카운터 (요금 폭탄 방어)
_sms_sent_log = []  # epoch 초 리스트

def _sms_rate_ok():
    now = time.time()
    cutoff = now - 3600
    while _sms_sent_log and _sms_sent_log[0] < cutoff:
        _sms_sent_log.pop(0)
    return len(_sms_sent_log) < SMS_HOURLY_CAP

async def _send_sms_alert(mon):
    # 모니터별 번호(밸브에서 전달) 우선, 없으면 서버 전역 SMS_NOTIFY_TO
    raw = (mon.get("sms_to") or "").strip() or SMS_NOTIFY_TO
    if not raw:
        return
    # 쉼표/세미콜론 분리 → 중복 제거
    nums, seen = [], set()
    for n in raw.replace(";", ",").split(","):
        n = n.strip()
        if n and n not in seen:
            seen.add(n); nums.append(n)
    # [보안1] E.164 형식 검증 — 형식 틀린 번호 제거
    valid = []
    for n in nums:
        if not _sms_valid(n):
            logger.warning(f"SMS 번호 형식 무효, 제외: {_sms_mask(n)}")
        elif not _sms_allowed(n):
            # [보안2] 화이트리스트 이탈 차단
            logger.warning(f"SMS 허용목록 외 번호, 차단: {_sms_mask(n)}")
        else:
            valid.append(n)
    if not valid:
        return
    # [보안3] 1회 인원 상한
    if len(valid) > SMS_MAX_RECIPIENTS:
        logger.warning(f"SMS 수신자 {len(valid)}명 → 상한 {SMS_MAX_RECIPIENTS}명 제한")
        valid = valid[:SMS_MAX_RECIPIENTS]
    label = mon.get("label") or mon.get("keyword") or "모니터"
    tv    = mon.get("target_value") or ""
    cur   = (mon.get("last_value") or "")[:80]
    body  = f"🔔 {label}: 목표값 '{tv}' 도달\n현재: {cur}\n{mon.get('url','')[:80]}"
    sent = 0
    for to in valid:
        # [보안4] 시간당 총량 상한 — 요금 폭탄 방어
        if not _sms_rate_ok():
            logger.warning(f"SMS 시간당 상한({SMS_HOURLY_CAP}) 도달 — 발송 중단")
            break
        try:
            async with httpx.AsyncClient(timeout=10) as c:
                r = await c.post(SMS_NOTIFY_URL, json={"to": to, "message": body})
            if r.status_code == 200:
                sent += 1
                _sms_sent_log.append(time.time())
            else:
                logger.warning(f"SMS 실패({_sms_mask(to)}, HTTP {r.status_code})")
        except Exception as e:
            logger.warning(f"SMS 예외({_sms_mask(to)}): {type(e).__name__}")
    if sent:
        logger.info(f"📱 SMS 알림 {sent}/{len(valid)}명 전송")

async def _monitor_loop():
    await asyncio.sleep(120)
    while True:
        try:
            now = time.time()
            for mid, mon in list(_monitors.items()):
                if mon.get("triggered"): continue
                interval_sec = mon.get("interval_minutes", 60) * 60
                last = mon.get("last_checked")
                if last:
                    lt = time.mktime(time.strptime(last, "%Y-%m-%dT%H:%M:%S"))
                    if now - lt < interval_sec: continue
                llm = create_llm()
                if not llm: continue
                try:
                    from browser_use import Agent
                    from browser_use import BrowserSession; from browser_use.browser import BrowserProfile
                    proxy_cfg = BrowserProfile(headless=True, proxy={"server":BROWSER_PROXY} if BROWSER_PROXY else None)
                    s  = BrowserSession(browser_profile=proxy_cfg)
                    ag = Agent(task=f"URL: {mon['url']}\n{mon['keyword']} 현재값을 알려줘.",
                               llm=llm, browser_session=s, use_vision=False, max_actions_per_step=5)
                    r  = await asyncio.wait_for(ag.run(max_steps=6), timeout=60)
                    await asyncio.wait_for(s.close(), timeout=5)
                    cv = filter_response(r.final_result() or "")
                    mon.update({"last_checked":time.strftime("%Y-%m-%dT%H:%M:%S"),"last_value":cv[:200]})
                    if mon.get("target_value") and mon["target_value"] in cv:
                        mon["triggered"] = True; logger.info(f"🔔 모니터 트리거: {mid}")
                        await _send_sms_alert(mon)
                    _save_monitors()
                except Exception as e: logger.warning(f"모니터[{mid}]: {e}")
        except Exception as e: logger.error(f"모니터 루프: {e}")
        await asyncio.sleep(300)

"""

MARKER = 'if __name__ == "__main__":'
if MARKER in code:
    code = code.replace(MARKER, NEW_EPS + MARKER)
    ok_list.append('엔드포인트 9개')

# 브라우저 풀 warm_up 연결
OLD_MN = '_init_monitors()\n    asyncio.create_task(_monitor_loop())'
if OLD_MN in code:
    code = code.replace(OLD_MN,
        OLD_MN + '\n    if _browser_pool:\n        asyncio.create_task(_browser_pool.warm_up())')
    ok_list.append('브라우저 풀 warm-up')

with open(agent_path, 'w', encoding='utf-8') as f: f.write(code)
print(f"  📋 적용: {len(ok_list)}개")
for p in ok_list: print(f"    ✅ {p}")
print(f"  📋 최종 라인: {len(code.splitlines())}")
UPGRADE_PATCH

ok "agent_server.py 업그레이드 완료"

############################################
# 4-3. agent_server.py 사용자별 메모리 분리 (이메일 기준)
# - X-User-Id 헤더(이메일)로 사용자 식별
# - /app/data/memory/{sha256[:16]}.json 사용자별 파일
# - 헤더 없으면 기존 단일 파일로 폴백 (하위 호환)
############################################
step "4-3/9  사용자별 메모리 분리 (이메일 기준)"

AGENT_DIR="${AGENT_DIR}" python3 << 'PERUSER_PATCH'
import os, sys

agent_path = os.environ.get('AGENT_DIR','') + '/agent_server.py'
try:
    with open(agent_path, encoding='utf-8') as f: code = f.read()
except FileNotFoundError:
    print(f"  ❌ 파일 없음: {agent_path}"); sys.exit(1)

ok_list = []

# ── 1) 사용자별 메모리 헬퍼 + 함수 시그니처 교체 ──────────────────
OLD_MEM_BLOCK = '''MEMORY_FILE = _Path("/app/data/user_memory.json")
ALLOWED_FILE_EXT = {".txt",".md",".csv",".json",".pdf",".xlsx",".xls",".docx",".html",".xml",".log",".py",".sh"}
USER_FILES_DIR = _Path("/app/data/user_files")

def _load_memory() -> dict:
    try:
        if MEMORY_FILE.exists():
            return _json.loads(MEMORY_FILE.read_text("utf-8"))
    except Exception:
        pass
    return {"location":"","interests":[],"preferences":{},"facts":[],"past_queries":[]}

def _save_memory(mem: dict):
    try:
        MEMORY_FILE.parent.mkdir(parents=True, exist_ok=True)
        MEMORY_FILE.write_text(_json.dumps(mem, ensure_ascii=False, indent=2), "utf-8")
    except Exception as e:
        logger.error(f"Memory save failed: {e}")'''

NEW_MEM_BLOCK = '''MEMORY_FILE = _Path("/app/data/user_memory.json")  # [LEGACY] 헤더 없을 때 폴백
MEMORY_DIR = _Path("/app/data/memory")             # [PER-USER] 사용자별 메모리 디렉토리
ALLOWED_FILE_EXT = {".txt",".md",".csv",".json",".pdf",".xlsx",".xls",".docx",".html",".xml",".log",".py",".sh"}
USER_FILES_DIR = _Path("/app/data/user_files")

import hashlib as _hashlib2

# [MULTI-USER] uid 없을 때 공용 파일로 합치는 폴백을 막을지 여부.
# 여러 사용자가 쓰는 환경에서는 REQUIRE_USER_ID=true 로 설정 → 식별 실패 시 거부.
_REQUIRE_USER_ID = os.getenv("REQUIRE_USER_ID", "false").lower() == "true"

class MemoryUserRequired(Exception):
    """REQUIRE_USER_ID=true 인데 user_id 가 비어 메모리 접근을 거부할 때."""
    pass

def _memory_path(user_id: str = "") -> _Path:
    """[PER-USER] 이메일(user_id) → 안전한 사용자별 메모리 파일 경로.
    REQUIRE_USER_ID=false: uid 가 비면 단일 파일(MEMORY_FILE)로 폴백 (단독 사용 하위호환).
    REQUIRE_USER_ID=true : uid 가 비면 MemoryUserRequired 예외 → 공용 파일 오염 차단."""
    uid = (user_id or "").strip().lower()
    if not uid:
        if _REQUIRE_USER_ID:
            raise MemoryUserRequired("user_id required but missing")
        return MEMORY_FILE
    # 이메일 등 임의 문자열을 sha256 16자리로 해싱 → 경로 탈출·특수문자 원천 차단
    h = _hashlib2.sha256(uid.encode("utf-8")).hexdigest()[:16]
    return MEMORY_DIR / f"{h}.json"

def _load_memory(user_id: str = "") -> dict:
    try:
        p = _memory_path(user_id)
        if p.exists():
            return _json.loads(p.read_text("utf-8"))
    except MemoryUserRequired:
        # 식별 실패 → 빈 메모리 반환(공용 데이터 노출 금지)
        return {"location":"","interests":[],"preferences":{},"facts":[],"past_queries":[]}
    except Exception:
        pass
    return {"location":"","interests":[],"preferences":{},"facts":[],"past_queries":[]}

def _save_memory(mem: dict, user_id: str = ""):
    try:
        p = _memory_path(user_id)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(_json.dumps(mem, ensure_ascii=False, indent=2), "utf-8")
    except MemoryUserRequired:
        # 식별 실패 → 저장 거부(공용 파일 오염 방지). 조용히 건너뜀.
        audit_logger.warning("MEMORY_SAVE_DENIED|no_user_id")
    except Exception as e:
        logger.error(f"Memory save failed: {e}")'''

if OLD_MEM_BLOCK in code:
    code = code.replace(OLD_MEM_BLOCK, NEW_MEM_BLOCK)
    ok_list.append("메모리 함수 사용자별 경로화 (_memory_path)")
else:
    print("  ⚠️  메모리 함수 블록 위치 불일치")

# ── 2) _update_memory_from_task / _get_memory_context 에 user_id 전파 ──
OLD_UPD_SIG = 'def _update_memory_from_task(task: str, result: str):\n    """작업 기록에서 자동으로 사용자 정보 학습"""\n    mem = _load_memory()'
NEW_UPD_SIG = 'def _update_memory_from_task(task: str, result: str, user_id: str = ""):\n    """작업 기록에서 자동으로 사용자 정보 학습"""\n    mem = _load_memory(user_id)'
if OLD_UPD_SIG in code:
    code = code.replace(OLD_UPD_SIG, NEW_UPD_SIG)
    ok_list.append("_update_memory_from_task user_id 전파")

# _update_memory_from_task 끝의 _save_memory(mem) → _save_memory(mem, user_id)
OLD_UPD_SAVE = '''            mem["interests"] = mem["interests"][-20:]
    _save_memory(mem)'''
NEW_UPD_SAVE = '''            mem["interests"] = mem["interests"][-20:]
    _save_memory(mem, user_id)'''
if OLD_UPD_SAVE in code:
    code = code.replace(OLD_UPD_SAVE, NEW_UPD_SAVE)
    ok_list.append("_update_memory_from_task 저장 user_id")

OLD_CTX_SIG = 'def _get_memory_context() -> str:\n    """LLM 프롬프트에 주입할 메모리 컨텍스트"""\n    mem = _load_memory()'
NEW_CTX_SIG = 'def _get_memory_context(user_id: str = "") -> str:\n    """LLM 프롬프트에 주입할 메모리 컨텍스트"""\n    mem = _load_memory(user_id)'
if OLD_CTX_SIG in code:
    code = code.replace(OLD_CTX_SIG, NEW_CTX_SIG)
    ok_list.append("_get_memory_context user_id 전파")

# ── 3) 요청 헤더에서 user_id(이메일) 추출 헬퍼 추가 ──────────────
HELPER = '''def _req_user_id(request: Request) -> str:
    """[PER-USER] X-User-Id 헤더(이메일)에서 사용자 식별값 추출. 없으면 빈 문자열."""
    try:
        uid = request.headers.get("X-User-Id", "") or ""
        return uid.strip()[:200]
    except Exception:
        return ""

'''
# _get_memory_context 정의 바로 앞에 헬퍼 삽입
anchor = 'def _get_memory_context(user_id: str = "") -> str:'
if anchor in code and "_req_user_id" not in code:
    code = code.replace(anchor, HELPER + anchor, 1)
    ok_list.append("_req_user_id 헤더 추출 헬퍼 추가")

# ── 4) /browse 엔드포인트: 헤더에서 uid 읽어 메모리 호출에 전달 ──
OLD_BROWSE_CTX = '''    # 메모리 컨텍스트 주입
    mem_ctx = _get_memory_context()
    raw_task = body.task'''
NEW_BROWSE_CTX = '''    # 메모리 컨텍스트 주입 (사용자별)
    _uid = _req_user_id(request)
    mem_ctx = _get_memory_context(_uid)
    raw_task = body.task'''
if OLD_BROWSE_CTX in code:
    code = code.replace(OLD_BROWSE_CTX, NEW_BROWSE_CTX)
    ok_list.append("/browse 사용자별 컨텍스트")

OLD_BROWSE_UPD = '''            _update_memory_from_task(raw_task, result.get("summary",""))'''
NEW_BROWSE_UPD = '''            _update_memory_from_task(raw_task, result.get("summary",""), _uid)'''
if OLD_BROWSE_UPD in code:
    code = code.replace(OLD_BROWSE_UPD, NEW_BROWSE_UPD)
    ok_list.append("/browse 사용자별 학습 저장")

# ── 5) /browse/multitab: uid 전파 ───────────────────────────────
OLD_MT_UPD = '''    # 메모리 업데이트
    _update_memory_from_task(body.task, final_summary[:500])'''
NEW_MT_UPD = '''    # 메모리 업데이트 (사용자별)
    _update_memory_from_task(body.task, final_summary[:500], _req_user_id(request))'''
if OLD_MT_UPD in code:
    code = code.replace(OLD_MT_UPD, NEW_MT_UPD)
    ok_list.append("/browse/multitab 사용자별 학습")

# ── 6) /memory GET·POST·DELETE 엔드포인트 사용자별화 ────────────
OLD_GET = '''@app.get("/memory")
async def get_memory(_=Depends(verify_api_key)):
    return _load_memory()'''
NEW_GET = '''@app.get("/memory")
async def get_memory(request: Request, _=Depends(verify_api_key)):
    return _load_memory(_req_user_id(request))'''
if OLD_GET in code:
    code = code.replace(OLD_GET, NEW_GET)
    ok_list.append("/memory GET 사용자별")

OLD_POST = '''@app.post("/memory")
async def update_memory(request: Request, _=Depends(verify_api_key)):
    body = await request.json()
    body = validate_memory_update(body)  # [SECURITY] 스키마 검증
    mem = _load_memory()'''
NEW_POST = '''@app.post("/memory")
async def update_memory(request: Request, _=Depends(verify_api_key)):
    _uid = _req_user_id(request)
    if _REQUIRE_USER_ID and not _uid:
        raise HTTPException(400, "user identification required (X-User-Id missing)")
    body = await request.json()
    body = validate_memory_update(body)  # [SECURITY] 스키마 검증
    mem = _load_memory(_uid)'''
if OLD_POST in code:
    code = code.replace(OLD_POST, NEW_POST)
    ok_list.append("/memory POST 사용자별 로드")

OLD_POST_SAVE = '''    if "facts" in body: mem["facts"] = (mem.get("facts",[]) + [str(f)[:200] for f in body["facts"]])[-30:]
    _save_memory(mem)
    audit_logger.info(f"MEMORY_UPDATE|{list(body.keys())}")'''
NEW_POST_SAVE = '''    if "facts" in body: mem["facts"] = (mem.get("facts",[]) + [str(f)[:200] for f in body["facts"]])[-30:]
    _save_memory(mem, _uid)
    audit_logger.info(f"MEMORY_UPDATE|uid={'set' if _uid else 'none'}|{list(body.keys())}")'''
if OLD_POST_SAVE in code:
    code = code.replace(OLD_POST_SAVE, NEW_POST_SAVE)
    ok_list.append("/memory POST 사용자별 저장")

OLD_DEL = '''@app.delete("/memory")
async def clear_memory(_=Depends(verify_api_key)):
    _save_memory({"location":"","interests":[],"preferences":{},"facts":[],"past_queries":[]})
    return {"success": True, "message": "Memory cleared"}'''
NEW_DEL = '''@app.delete("/memory")
async def clear_memory(request: Request, _=Depends(verify_api_key)):
    _save_memory({"location":"","interests":[],"preferences":{},"facts":[],"past_queries":[]}, _req_user_id(request))
    return {"success": True, "message": "Memory cleared"}'''
if OLD_DEL in code:
    code = code.replace(OLD_DEL, NEW_DEL)
    ok_list.append("/memory DELETE 사용자별")

# ── 7) /browse/multi 사용자별 메모리 연동 (텔레그램 X-User-Id: tg:* 경로) ──
#    멀티 에이전트는 원래 메모리를 안 썼음 → 작업 전 컨텍스트 주입 + 작업 후 학습 추가
OLD_MULTI_GRAPH = '''    async with task_slot():
        try:
            graph = build_graph()
            state = {"original_task": body.task, "messages": [],'''
NEW_MULTI_GRAPH = '''    _uid = _req_user_id(request)
    _mem_ctx = _get_memory_context(_uid)
    _multi_task = (_mem_ctx + "\\n\\n" + body.task) if _mem_ctx else body.task
    async with task_slot():
        try:
            graph = build_graph()
            state = {"original_task": _multi_task, "messages": [],'''
if OLD_MULTI_GRAPH in code:
    code = code.replace(OLD_MULTI_GRAPH, NEW_MULTI_GRAPH)
    ok_list.append("/browse/multi 사용자별 컨텍스트 주입")
else:
    print("  ⚠️  /browse/multi graph 블록 위치 불일치")

OLD_MULTI_RET = '''            audit_logger.info(f"MULTI_OK|tokens={token_info.get('total_tokens',0)}")
            return {"success": True, "result": last,'''
NEW_MULTI_RET = '''            try:
                _update_memory_from_task(body.task, str(last)[:500], _uid)
            except Exception:
                pass
            audit_logger.info(f"MULTI_OK|tokens={token_info.get('total_tokens',0)}|uid={'set' if _uid else 'none'}")
            return {"success": True, "result": last,'''
if OLD_MULTI_RET in code:
    code = code.replace(OLD_MULTI_RET, NEW_MULTI_RET)
    ok_list.append("/browse/multi 사용자별 학습 저장")
else:
    print("  ⚠️  /browse/multi return 블록 위치 불일치")

with open(agent_path, 'w', encoding='utf-8') as f:
    f.write(code)

print(f"  📋 적용: {len(ok_list)}개")
for p in ok_list: print(f"    ✅ {p}")
print(f"  📋 최종 라인: {len(code.splitlines())}")
PERUSER_PATCH

ok "사용자별 메모리 분리 완료 (agent_server.py)"

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
    "qwen/qwen3.8-27b":{"context":131072,"max_output":32768,"in_cost":0.59,"out_cost":0.79},
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
    return text[:int(len(text)*(mt/est_tok(text))*0.9)] + "\n[...절삭]"

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
    heavy: str = "qwen/qwen3.8-27b"
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
PROMPT=('Supervisor. JSON만 출력: {"next":"research|browser|summarizer","reason":"이유"}\n'
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
    msgs=[SystemMessage(content=PROMPT),HumanMessage(content="\n".join(ctx))]
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
PROMPT=("리서치 에이전트. 체계적으로 조사.\n"
        "불확실→[확인 필요], 브라우저 필요→[브라우저 필요: URL]. 한국어.")

async def research_node(state: AgentState) -> dict[str, Any]:
    task=state.get("original_task",""); ex=state.get("research_results",[])
    bro=state.get("browser_results",[]); tr=state.get("token_tracker")
    sr=trunc_list(ex,3000); sb=trunc_list(bro,2000)
    p=[f"요청: {task}"]
    if sr: p.append("[이전조사]\n"+"\n---\n".join(sr))
    if sb: p.append("[브라우저데이터]\n"+"\n---\n".join(sb))
    if ex: p.append("중복없이 보완만.")
    user="\n".join(p)
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
        return C(model_name=os.environ.get("GROQ_MODEL","qwen/qwen3.8-27b"),
                 api_key=key, temperature=0, max_retries=3)

async def _search_via_api(task, display=5):
    """[v7] 같은 컨테이너의 /search 엔드포인트(네이버 Search API 전용) 호출.
    멀티 에이전트 browser 노드가 브라우저 긁기 대신 검색 API 를 쓴다.
    키가 없거나 결과가 비면 None 을 반환해 호출측이 브라우징으로 폴백한다."""
    import httpx
    base = os.environ.get("INTERNAL_SEARCH_URL", "http://localhost:8001")
    api_key = os.environ.get("BROWSER_AGENT_API_KEY", "")
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = "Bearer " + api_key
    # URL 이 통째로 들어온 작업은 검색 대상이 아니라 '페이지 열기'이므로 건너뜀
    if re.search(r"https?://", task):
        return None
    try:
        async with httpx.AsyncClient(timeout=20) as c:
            r = await c.post(base.rstrip("/") + "/search",
                             json={"query": task[:500], "kind": "auto", "display": display},
                             headers=headers)
        if r.status_code != 200:
            return None
        data = r.json()
        if data.get("success") and data.get("summary_plain"):
            return data["summary_plain"]
        return None
    except Exception as e:
        logger.warning("search api failed: %s", e)
        return None

async def _run_browser_task_legacy(task, max_steps=7):
    """기존 Browser Use 경로 (폴백용)."""
    llm = _get_llm()
    if not llm: return "[오류] GROQ_API_KEY 미설정"
    session = None
    try:
        session = BrowserSession(browser_profile=BrowserProfile(
            headless=True, viewport={"width": 1280, "height": 720}))
        agent = Agent(task=task, llm=llm, browser_session=session,
                      use_vision=False, max_actions_per_step=3)
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

async def _run_browser_task(task, max_steps=7):
    # [v7] 먼저 검색 API 시도 → 실패 시 기존 브라우징으로 폴백
    via_search = await _search_via_api(task)
    if via_search:
        return "[검색]" + via_search
    return await _run_browser_task_legacy(task, max_steps)

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
PROMPT=("수집 결과 종합→최종 답변. 비교→표, 추천→순위. 한국어 Markdown.\n"
        "마지막에 [Multi-Agent 조사 완료] 표기.")

async def summarizer_node(state: AgentState) -> dict[str, Any]:
    task=state.get("original_task","")
    res=state.get("research_results",[]); bro=state.get("browser_results",[])
    tr=state.get("token_tracker")
    sr=trunc_list(res,6000); sb=trunc_list(bro,4000)
    p=[f"## 요청\n{task}"]
    if sr: p.extend([f"### 조사#{i+1}\n{r}" for i,r in enumerate(sr)])
    if sb: p.extend([f"### 수집#{i+1}\n{b}" for i,b in enumerate(sb)])
    data="\n\n".join(p)
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

async def run_multi_agent(task, model="qwen/qwen3.8-27b", budget_usd=0.0):
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
    "upDsi5wg7Jyg7ZqoIOyLnOqwhCAo7LSILCAwPeu5hO2ZnOyEse2ZlCkiKQogICAgICAgIFNNU19O"
    "T1RJRllfVE86IHN0ciA9IEZpZWxkKGRlZmF1bHQ9IiIsIGRlc2NyaXB0aW9uPSLqsIDqsqkg66qo"
    "64uI7YSw66eBIOyVjOumvCBTTVMg7IiY7IugIOuyiO2YuC4g7Jes65+sIOuqheydgCDsibztkZzr"
    "oZwg6rWs67aEICjsmIg6ICs4MjEwMTExMTIyMjIsICs4MjEwMzMzMzQ0NDQpLiDruYTsmrDrqbQg"
    "U01TIOyViCDrs7Trg4QiKQogICAgICAgIE1PTklUT1JfQURNSU5fT05MWTogYm9vbCA9IEZpZWxk"
    "KGRlZmF1bHQ9VHJ1ZSwgZGVzY3JpcHRpb249IuqwgOqyqSDrqqjri4jthLDrp4Eg65Ox66Gd7J2E"
    "IOq0gOumrOyekOunjCDtl4jsmqkgKFNNUyDsmpTquIgg67O07Zi4LCDqtozsnqUpIikKCiAgICBk"
    "ZWYgX19pbml0X18oc2VsZik6CiAgICAgICAgc2VsZi52YWx2ZXMgPSBzZWxmLlZhbHZlcygpCiAg"
    "ICAgICAgc2VsZi5fc2Vzc2lvbl9pZDogT3B0aW9uYWxbc3RyXSA9IE5vbmUKICAgICAgICBzZWxm"
    "Ll9jYWNoZTogRGljdFtzdHIsIGRpY3RdID0ge30KCiAgICBkZWYgX2hlYWRlcnMoc2VsZikgLT4g"
    "ZGljdDoKICAgICAgICBoZWFkZXJzID0geyJDb250ZW50LVR5cGUiOiAiYXBwbGljYXRpb24vanNv"
    "biJ9CiAgICAgICAgaWYgc2VsZi52YWx2ZXMuQlJPV1NFUl9BR0VOVF9BUElfS0VZOgogICAgICAg"
    "ICAgICBoZWFkZXJzWyJBdXRob3JpemF0aW9uIl0gPSBmIkJlYXJlciB7c2VsZi52YWx2ZXMuQlJP"
    "V1NFUl9BR0VOVF9BUElfS0VZfSIKICAgICAgICByZXR1cm4gaGVhZGVycwoKICAgIGRlZiBfZ2V0"
    "X2NhY2hlKHNlbGYsIGtleSk6CiAgICAgICAgaWYgc2VsZi52YWx2ZXMuQ0FDSEVfVFRMIDw9IDA6"
    "IHJldHVybiBOb25lCiAgICAgICAgZW50cnkgPSBzZWxmLl9jYWNoZS5nZXQoa2V5KQogICAgICAg"
    "IGlmIGVudHJ5IGFuZCB0aW1lLnRpbWUoKSAtIGVudHJ5WyJ0cyJdIDwgc2VsZi52YWx2ZXMuQ0FD"
    "SEVfVFRMOiByZXR1cm4gZW50cnlbImRhdGEiXQogICAgICAgIHJldHVybiBOb25lCgogICAgZGVm"
    "IF9zZXRfY2FjaGUoc2VsZiwga2V5LCBkYXRhKToKICAgICAgICBpZiBzZWxmLnZhbHZlcy5DQUNI"
    "RV9UVEwgPiAwOgogICAgICAgICAgICBzZWxmLl9jYWNoZVtrZXldID0geyJkYXRhIjogZGF0YSwg"
    "InRzIjogdGltZS50aW1lKCl9CiAgICAgICAgICAgIGlmIGxlbihzZWxmLl9jYWNoZSkgPiA1MDoK"
    "ICAgICAgICAgICAgICAgIG9sZGVzdCA9IG1pbihzZWxmLl9jYWNoZSwga2V5PWxhbWJkYSBrOiBz"
    "ZWxmLl9jYWNoZVtrXVsidHMiXSkKICAgICAgICAgICAgICAgIGRlbCBzZWxmLl9jYWNoZVtvbGRl"
    "c3RdCgogICAgYXN5bmMgZGVmIF9wb3N0KHNlbGYsIHBhdGgsIHBheWxvYWQpOgogICAgICAgIGlt"
    "cG9ydCBodHRweAogICAgICAgIGlmIGlzaW5zdGFuY2UocGF5bG9hZCwgZGljdCk6CiAgICAgICAg"
    "ICAgIGlmIHNlbGYudmFsdmVzLkxMTV9QUk9WSURFUjogcGF5bG9hZC5zZXRkZWZhdWx0KCJwcm92"
    "aWRlciIsIHNlbGYudmFsdmVzLkxMTV9QUk9WSURFUikKICAgICAgICAgICAgaWYgc2VsZi52YWx2"
    "ZXMuTExNX0FQSV9LRVk6IHBheWxvYWQuc2V0ZGVmYXVsdCgiYXBpX2tleSIsIHNlbGYudmFsdmVz"
    "LkxMTV9BUElfS0VZKQogICAgICAgICAgICBpZiBzZWxmLnZhbHZlcy5MTE1fTU9ERUw6IHBheWxv"
    "YWQuc2V0ZGVmYXVsdCgibW9kZWwiLCBzZWxmLnZhbHZlcy5MTE1fTU9ERUwpCiAgICAgICAgdXJs"
    "ID0gc2VsZi52YWx2ZXMuQlJPV1NFUl9BR0VOVF9VUkwucnN0cmlwKCIvIikgKyBwYXRoCiAgICAg"
    "ICAgYXN5bmMgd2l0aCBodHRweC5Bc3luY0NsaWVudCh0aW1lb3V0PXNlbGYudmFsdmVzLlJFUVVF"
    "U1RfVElNRU9VVCkgYXMgYzoKICAgICAgICAgICAgciA9IGF3YWl0IGMucG9zdCh1cmwsIGpzb249"
    "cGF5bG9hZCwgaGVhZGVycz1zZWxmLl9oZWFkZXJzKCkpCiAgICAgICAgICAgIGlmIHIuc3RhdHVz"
    "X2NvZGUgPT0gNDAxOiByYWlzZSBQZXJtaXNzaW9uRXJyb3IoIkFQSSDtgqQg7J247KadIOyLpO2M"
    "qCIpCiAgICAgICAgICAgIGlmIHIuc3RhdHVzX2NvZGUgPT0gNDAzOiByYWlzZSBQZXJtaXNzaW9u"
    "RXJyb3IoIuygkeq3vCDqsbDrtoAiKQogICAgICAgICAgICBpZiByLnN0YXR1c19jb2RlID09IDQy"
    "OTogcmFpc2UgUnVudGltZUVycm9yKCLsmpTssq0g7ZWc64+EIOy0iOqzvCIpCiAgICAgICAgICAg"
    "IHIucmFpc2VfZm9yX3N0YXR1cygpCiAgICAgICAgICAgIGRhdGEgPSByLmpzb24oKQogICAgICAg"
    "ICAgICBpZiBpc2luc3RhbmNlKGRhdGEsIGRpY3QpIGFuZCBkYXRhLmdldCgic3VjY2VzcyIpIGlz"
    "IEZhbHNlOgogICAgICAgICAgICAgICAgcmFpc2UgUnVudGltZUVycm9yKCLruIzrnbzsmrDsoIAg"
    "7JeQ7J207KCE7Yq4IOyYpOulmDogIiArIGRhdGEuZ2V0KCJlcnJvciIsICIiKSkKICAgICAgICAg"
    "ICAgcmV0dXJuIGRhdGEKCiAgICBhc3luYyBkZWYgYnJvd3NlKHNlbGYsIHRhc2s6IHN0ciwgX19l"
    "dmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiT3BlbiBhIFVSTCBhbmQgcGVyZm9ybSBh"
    "IHRhc2suIERvIE5PVCB1c2UgZm9yIHdlYXRoZXIvcHJpY2VzL3N0b2NrcyAtIHVzZSBkZWRpY2F0"
    "ZWQgZnVuY3Rpb25zLgogICAgICAgIDpwYXJhbSB0YXNrOiBVUkwgKyBpbnN0cnVjdGlvbgogICAg"
    "ICAgICIiIgogICAgICAgIGFzeW5jIGRlZiBlbWl0KG1zZywgZG9uZT1GYWxzZSk6CiAgICAgICAg"
    "ICAgIGlmIF9fZXZlbnRfZW1pdHRlcl9fOiBhd2FpdCBfX2V2ZW50X2VtaXR0ZXJfXyh7InR5cGUi"
    "OiJzdGF0dXMiLCJkYXRhIjp7ImRlc2NyaXB0aW9uIjptc2csImRvbmUiOmRvbmV9fSkKICAgICAg"
    "ICBpZiBsZW4odGFzay5zdHJpcCgpKSA8IDI6IHJldHVybiAi7J6R7JeFIOuCtOyaqeydtCDrhIjr"
    "rLQg7Ken7Iq164uI64ukLiIKICAgICAgICBhd2FpdCBlbWl0KCLruIzrnbzsmrDsoIDrpbwg7Je0"
    "6rOgIOyekeyXhSDspJEuLi4iKQogICAgICAgIHRyeToKICAgICAgICAgICAgcmVzdWx0ID0gYXdh"
    "aXQgc2VsZi5fcG9zdCgiL2Jyb3dzZSIsIHsidGFzayI6IHRhc2ssICJtYXhfc3RlcHMiOiBzZWxm"
    "LnZhbHZlcy5ERUZBVUxUX01BWF9TVEVQU30pCiAgICAgICAgICAgIGF3YWl0IGVtaXQoIuyZhOuj"
    "jCEiLCBkb25lPVRydWUpCiAgICAgICAgICAgIHJldHVybiByZXN1bHQuZ2V0KCJzdW1tYXJ5X3Bs"
    "YWluIikgb3IgcmVzdWx0LmdldCgic3VtbWFyeSIsICLsnpHsl4Ug7JmE66OMIikKICAgICAgICBl"
    "eGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAgICAgICAgICAgIGF3YWl0IGVtaXQoIuyYpOulmCIsIGRv"
    "bmU9VHJ1ZSkKICAgICAgICAgICAgcmV0dXJuIGYi7Jik66WYOiB7ZX0iCgogICAgYXN5bmMgZGVm"
    "IF9hcGlfc2VhcmNoKHNlbGYsIHF1ZXJ5LCBraW5kPSJhdXRvIiwgZGlzcGxheT01LCBfX2V2ZW50"
    "X2VtaXR0ZXJfXz1Ob25lKToKICAgICAgICAiIiJicm93c2VyLWFnZW50IOydmCAvc2VhcmNoIOyX"
    "lOuTnO2PrOyduO2KuCDtmLjstpwgKOuEpOydtOuyhCBTZWFyY2ggQVBJIOyghOyaqSkuCiAgICAg"
    "ICAg67iM65287Jqw7KCAIOq4geq4sCDrjIDsi6Ag64Sk7J2067KEIOqzteyLnSBTZWFyY2ggQVBJ"
    "IOulvCDsgqzsmqntlZzri6QuIiIiCiAgICAgICAgY2FjaGVkID0gc2VsZi5fZ2V0X2NhY2hlKCJz"
    "ZWFyY2g6JXM6JXMiICUgKGtpbmQsIHF1ZXJ5KSkKICAgICAgICBpZiBjYWNoZWQ6IHJldHVybiBj"
    "YWNoZWQKICAgICAgICBhc3luYyBkZWYgZW1pdChtc2csIGRvbmU9RmFsc2UpOgogICAgICAgICAg"
    "ICBpZiBfX2V2ZW50X2VtaXR0ZXJfXzogYXdhaXQgX19ldmVudF9lbWl0dGVyX18oeyJ0eXBlIjoi"
    "c3RhdHVzIiwiZGF0YSI6eyJkZXNjcmlwdGlvbiI6bXNnLCJkb25lIjpkb25lfX0pCiAgICAgICAg"
    "YXdhaXQgZW1pdCgi6rKA7IOJIOykkS4uLiIpCiAgICAgICAgdHJ5OgogICAgICAgICAgICByZXN1"
    "bHQgPSBhd2FpdCBzZWxmLl9wb3N0KCIvc2VhcmNoIiwgeyJxdWVyeSI6IHF1ZXJ5LCAia2luZCI6"
    "IGtpbmQsICJkaXNwbGF5IjogZGlzcGxheX0pCiAgICAgICAgICAgIHRleHQgPSByZXN1bHQuZ2V0"
    "KCJzdW1tYXJ5X3BsYWluIikgb3IgcmVzdWx0LmdldCgic3VtbWFyeSIsICIiKQogICAgICAgICAg"
    "ICBhd2FpdCBlbWl0KCLsmYTro4whIiwgZG9uZT1UcnVlKQogICAgICAgICAgICBpZiB0ZXh0OiBz"
    "ZWxmLl9zZXRfY2FjaGUoInNlYXJjaDolczolcyIgJSAoa2luZCwgcXVlcnkpLCB0ZXh0KQogICAg"
    "ICAgICAgICByZXR1cm4gdGV4dCBvciAi6rKA7IOJIOqysOqzvOqwgCDsl4bsirXri4jri6QuIgog"
    "ICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgYXdhaXQgZW1pdCgi7Jik"
    "66WYIiwgZG9uZT1UcnVlKQogICAgICAgICAgICByZXR1cm4gIuqygOyDiSDsmKTrpZg6ICVzIiAl"
    "IGUKCiAgICBhc3luYyBkZWYgX25hdmVyX3NlYXJjaChzZWxmLCBxdWVyeV9rciwgaW5zdHJ1Y3Rp"
    "b24sIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICMgW3Y3XSDruIzrnbzsmrDsoIAg"
    "6riB6riwIOKGkiAvc2VhcmNoIOyXlOuTnO2PrOyduO2KuCjrhKTsnbTrsoQgU2VhcmNoIEFQSSDs"
    "oITsmqkpLiBpbnN0cnVjdGlvbiDsnYAKICAgICAgICAjIEFQSSDqsoDsg4nsl5DshJzripQg67aI"
    "7ZWE7JqU7ZWY66+A66GcIOustOyLnO2VmOqzoCBxdWVyeSDrp4wg7IKs7Jqp7ZWc64ukLgogICAg"
    "ICAgIHJldHVybiBhd2FpdCBzZWxmLl9hcGlfc2VhcmNoKHF1ZXJ5X2tyLCBraW5kPSJhdXRvIiwg"
    "X19ldmVudF9lbWl0dGVyX189X19ldmVudF9lbWl0dGVyX18pCgogICAgZGVmIF90cmFuc2xhdGVf"
    "a2V5d29yZChzZWxmLCBrZXl3b3JkOiBzdHIsIGtleXdvcmRfbWFwOiBkaWN0KSAtPiBzdHI6CiAg"
    "ICAgICAgIyDsmIHslrQg7YKk7JuM65Oc66W8IO2VnOq1reyWtOuhnCDsuZjtmZjtlZzri6QuCiAg"
    "ICAgICAgIyAtIOyghOyytOqwgCDsoJXtmZXtnogg7J287LmY7ZWY66m0IOuwlOuhnCDrp6TtlZHq"
    "sJIg67CY7ZmYCiAgICAgICAgIyAtIOu2gOu2hCDsuZjtmZjsnYAgJ+uLqOyWtCDqsr3qs4Qn7JeQ"
    "7ISc66eMIOyImO2WiSAobmV3c2xldHRlciDslYjsnZggbmV3cyDsmKTrp6Tsua0g67Cp7KeAKQog"
    "ICAgICAgICMgLSDrp6Tsua3rkJjsp4Ag7JWK7J2AIOu2gOu2hOydgCDsm5DrrLgg64yA7IaM66y4"
    "7J6Q66W8IOq3uOuMgOuhnCDrs7TsobQKICAgICAgICBpbXBvcnQgcmUgYXMgX3JlCiAgICAgICAg"
    "a3cgPSBrZXl3b3JkLnN0cmlwKCkKICAgICAgICBpZiBrdy5sb3dlcigpIGluIGtleXdvcmRfbWFw"
    "OgogICAgICAgICAgICByZXR1cm4ga2V5d29yZF9tYXBba3cubG93ZXIoKV0KICAgICAgICBmb3Ig"
    "ZW5nLCBrb3IgaW4gc29ydGVkKGtleXdvcmRfbWFwLml0ZW1zKCksIGtleT1sYW1iZGEgeDogLWxl"
    "bih4WzBdKSk6CiAgICAgICAgICAgIHBhdHRlcm4gPSByJyg/PCFbQS1aYS16MC05XSknICsgX3Jl"
    "LmVzY2FwZShlbmcpICsgcicoPyFbQS1aYS16MC05XSknCiAgICAgICAgICAgIGlmIF9yZS5zZWFy"
    "Y2gocGF0dGVybiwga3csIGZsYWdzPV9yZS5JR05PUkVDQVNFKToKICAgICAgICAgICAgICAgIHJl"
    "dHVybiBfcmUuc3ViKHBhdHRlcm4sIGtvciwga3csIGZsYWdzPV9yZS5JR05PUkVDQVNFKQogICAg"
    "ICAgIHJldHVybiBrZXl3b3JkCgogICAgYXN5bmMgZGVmIHNlYXJjaF9uYXZlcihzZWxmLCBrZXl3"
    "b3JkOiBzdHIsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIlNlYXJjaCBOYXZl"
    "ciBmb3IgcmVhbC10aW1lIGluZm9ybWF0aW9uLgogICAgICAgIDpwYXJhbSBrZXl3b3JkOiBTZWFy"
    "Y2gga2V5d29yZAogICAgICAgICIiIgogICAgICAgIGlmIG5vdCBrZXl3b3JkLnN0cmlwKCk6IHJl"
    "dHVybiAi6rKA7IOJ7Ja066W8IOyeheugpe2VmOyEuOyalC4iCiAgICAgICAga20gPSB7IndlYXRo"
    "ZXIiOiLrgqDslKgiLCJuZXdzIjoi64m07IqkIiwic3RvY2siOiLso7zqsIAiLCJleGNoYW5nZSBy"
    "YXRlIjoi7ZmY7JyoIiwicHJpY2UiOiLqsIDqsqkiLAogICAgICAgICAgICAgICJiaXRjb2luIjoi"
    "67mE7Yq47L2U7J24Iiwic29jY2VyIjoi7LaV6rWsIiwiYmFzZWJhbGwiOiLslbzqtawiLCJtb3Zp"
    "ZSI6IuyYge2ZlCIsInRyYXZlbCI6IuyXrO2WiSJ9CiAgICAgICAgcmV0dXJuIGF3YWl0IHNlbGYu"
    "X25hdmVyX3NlYXJjaChzZWxmLl90cmFuc2xhdGVfa2V5d29yZChrZXl3b3JkLCBrbSksCiAgICAg"
    "ICAgICAgICJyZWFkIHRoZSBrZXkgaW5mb3JtYXRpb24gZnJvbSBzZWFyY2ggcmVzdWx0cyBpbiBL"
    "b3JlYW4iLCBfX2V2ZW50X2VtaXR0ZXJfXykKCiAgICBhc3luYyBkZWYgdHJhbnNsYXRlKHNlbGYs"
    "IHRleHQ6IHN0ciwgdGFyZ2V0X2xhbmc6IHN0ciA9ICLtlZzqta3slrQiLCBfX2V2ZW50X2VtaXR0"
    "ZXJfXz1Ob25lKToKICAgICAgICAiIiJUcmFuc2xhdGUgdGV4dCBiZXR3ZWVuIGxhbmd1YWdlcyAo"
    "S29yZWFuLCBFbmdsaXNoLCBKYXBhbmVzZSwgQ2hpbmVzZSwgZXRjKS4KICAgICAgICA6cGFyYW0g"
    "dGV4dDog67KI7Jet7ZWgIOybkOusuAogICAgICAgIDpwYXJhbSB0YXJnZXRfbGFuZzog66qp7ZGc"
    "IOyWuOyWtCAo7JiIOiDtlZzqta3slrQsIOyYgeyWtCwg7J2867O47Ja0LCDspJHqta3slrQpLiDq"
    "uLDrs7gg7ZWc6rWt7Ja0LgogICAgICAgICIiIgogICAgICAgIHNyYyA9ICh0ZXh0IG9yICIiKS5z"
    "dHJpcCgpCiAgICAgICAgaWYgbm90IHNyYzogcmV0dXJuICLrsojsl63tlaAg64K07Jqp7J2EIOye"
    "heugpe2VmOyEuOyalC4iCiAgICAgICAgdGd0ID0gKHRhcmdldF9sYW5nIG9yICIiKS5zdHJpcCgp"
    "IG9yICLtlZzqta3slrQiCiAgICAgICAgaWYgbGVuKHNyYykgPiAzMDAwOiBzcmMgPSBzcmNbOjMw"
    "MDBdCiAgICAgICAgY2FjaGVfa2V5ID0gInRyOiIgKyB0Z3QgKyAiOiIgKyBzcmNbOjgwXQogICAg"
    "ICAgIGNhY2hlZCA9IHNlbGYuX2dldF9jYWNoZShjYWNoZV9rZXkpCiAgICAgICAgaWYgY2FjaGVk"
    "OiByZXR1cm4gY2FjaGVkCiAgICAgICAgYXN5bmMgZGVmIGVtaXQobXNnLCBkb25lPUZhbHNlKToK"
    "ICAgICAgICAgICAgaWYgX19ldmVudF9lbWl0dGVyX186IGF3YWl0IF9fZXZlbnRfZW1pdHRlcl9f"
    "KHsidHlwZSI6InN0YXR1cyIsImRhdGEiOnsiZGVzY3JpcHRpb24iOm1zZywiZG9uZSI6ZG9uZX19"
    "KQogICAgICAgIGF3YWl0IGVtaXQodGd0ICsgIijsnLwp66GcIOuyiOyXrSDspJEuLi4iKQogICAg"
    "ICAgIHRyeToKICAgICAgICAgICAgdGFzayA9ICgi64uk7J2MIO2FjeyKpO2KuOulvCAiICsgdGd0"
    "ICsgIuuhnCDrsojsl63tlZjshLjsmpQuIOuyiOyXrSDqsrDqs7zrp4wg7Lac66Cl7ZWY6rOgIOyE"
    "pOuqheydgCDrtpnsnbTsp4Ag66eI7IS47JqULlxuXG4iICsgc3JjKQogICAgICAgICAgICByZXN1"
    "bHQgPSBhd2FpdCBzZWxmLl9wb3N0KCIvYnJvd3NlIiwgeyJ0YXNrIjogdGFzaywgIm1heF9zdGVw"
    "cyI6IDF9KQogICAgICAgICAgICBvdXQgPSByZXN1bHQuZ2V0KCJzdW1tYXJ5X3BsYWluIikgb3Ig"
    "cmVzdWx0LmdldCgic3VtbWFyeSIsICIiKQogICAgICAgICAgICBhd2FpdCBlbWl0KCLsmYTro4wh"
    "IiwgZG9uZT1UcnVlKQogICAgICAgICAgICBpZiBvdXQ6IHNlbGYuX3NldF9jYWNoZShjYWNoZV9r"
    "ZXksIG91dCkKICAgICAgICAgICAgcmV0dXJuIG91dCBvciAi67KI7JetIOqysOqzvOulvCDqsIDs"
    "oLjsmKTsp4Ag66q77ZaI7Iq164uI64ukLiIKICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6"
    "CiAgICAgICAgICAgIGF3YWl0IGVtaXQoIuyYpOulmCIsIGRvbmU9VHJ1ZSkKICAgICAgICAgICAg"
    "cmV0dXJuICLrsojsl60g7Jik66WYOiAiICsgc3RyKGUpCgogICAgYXN5bmMgZGVmIGNoZWNrX3dl"
    "YXRoZXIoc2VsZiwgbG9jYXRpb246IHN0ciA9ICLshJzsmrgiLCB3aGVuOiBzdHIgPSAi7Jik64qY"
    "IiwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiQ2hlY2sgd2VhdGhlciBmcm9t"
    "IE5hdmVyLiBVc2UgZm9yIHdlYXRoZXIsIHRlbXBlcmF0dXJlLCByYWluLCB1bWJyZWxsYSwgZmlu"
    "ZSBkdXN0IHF1ZXN0aW9ucy4KICAgICAgICA6cGFyYW0gbG9jYXRpb246IOyngOyXreuqhSAo7JiI"
    "OiDshJzsmrgsIOu2gOyCsCwg7KCc7KO8KS4g7IKs7Jqp7J6Q6rCAIOyngOyXreydhCDrp5DtlZjs"
    "p4Ag7JWK7Jy866m0IOyEnOyauC4KICAgICAgICA6cGFyYW0gd2hlbjog7Iuc7KCQICjsmKTripgs"
    "IOuCtOydvCwg66qo66CILCDso7zrp5AsIOydtOuyiOyjvCkuIOyLnOygkOydhCDrp5DtlZjsp4Ag"
    "7JWK7Jy866m0IOyYpOuKmC4KICAgICAgICAiIiIKICAgICAgICBsb2MgPSAobG9jYXRpb24gb3Ig"
    "IiIpLnN0cmlwKCkgb3IgIuyEnOyauCIKICAgICAgICB3aCA9ICh3aGVuIG9yICIiKS5zdHJpcCgp"
    "IG9yICLsmKTripgiCiAgICAgICAgY2FjaGVfa2V5ID0gIndlYXRoZXI6IiArIGxvYyArICI6IiAr"
    "IHdoCiAgICAgICAgY2FjaGVkID0gc2VsZi5fZ2V0X2NhY2hlKGNhY2hlX2tleSkKICAgICAgICBp"
    "ZiBjYWNoZWQ6IHJldHVybiBjYWNoZWQKICAgICAgICBhc3luYyBkZWYgZW1pdChtc2csIGRvbmU9"
    "RmFsc2UpOgogICAgICAgICAgICBpZiBfX2V2ZW50X2VtaXR0ZXJfXzogYXdhaXQgX19ldmVudF9l"
    "bWl0dGVyX18oeyJ0eXBlIjoic3RhdHVzIiwiZGF0YSI6eyJkZXNjcmlwdGlvbiI6bXNnLCJkb25l"
    "Ijpkb25lfX0pCiAgICAgICAgYXdhaXQgZW1pdChsb2MgKyAiICIgKyB3aCArICIg64Kg7JSoIO2Z"
    "leyduCDspJEuLi4iKQogICAgICAgIHRyeToKICAgICAgICAgICAgd2VhdGhlciA9IGF3YWl0IHNl"
    "bGYuX2FwaV9zZWFyY2gobG9jICsgIiAiICsgd2ggKyAiIOuCoOyUqCDquLDsmKgg66+47IS466i8"
    "7KeAIiwga2luZD0iYXV0byIsIF9fZXZlbnRfZW1pdHRlcl9fPV9fZXZlbnRfZW1pdHRlcl9fKQog"
    "ICAgICAgICAgICBhd2FpdCBlbWl0KCLsmYTro4whIiwgZG9uZT1UcnVlKQogICAgICAgICAgICBp"
    "ZiB3ZWF0aGVyIGFuZCAi6rKA7IOJIOqysOqzvCIgbm90IGluIHdlYXRoZXJbOjhdIGFuZCAi7Jik"
    "66WYIiBub3QgaW4gd2VhdGhlcls6Nl06CiAgICAgICAgICAgICAgICBzZWxmLl9zZXRfY2FjaGUo"
    "Y2FjaGVfa2V5LCB3ZWF0aGVyKQogICAgICAgICAgICByZXR1cm4gd2VhdGhlciBvciAobG9jICsg"
    "IiAiICsgd2ggKyAiIOuCoOyUqCDsoJXrs7Trpbwg6rCA7KC47Jik7KeAIOuqu+2WiOyKteuLiOuL"
    "pC4iKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgYXdhaXQgZW1p"
    "dCgi7Jik66WYIiwgZG9uZT1UcnVlKQogICAgICAgICAgICByZXR1cm4gIuuCoOyUqCDtmZXsnbgg"
    "7Jik66WYOiAiICsgc3RyKGUpCgogICAgYXN5bmMgZGVmIGNoZWNrX3ByaWNlKHNlbGYsIHByb2R1"
    "Y3Q6IHN0ciwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiU2VhcmNoIHByb2R1"
    "Y3QgcHJpY2VzIG9uIE5hdmVyIFNob3BwaW5nLgogICAgICAgIDpwYXJhbSBwcm9kdWN0OiBQcm9k"
    "dWN0IG5hbWUKICAgICAgICAiIiIKICAgICAgICBpZiBub3QgcHJvZHVjdC5zdHJpcCgpOiByZXR1"
    "cm4gIuyDge2SiOuqheydhCDsnoXroKXtlZjshLjsmpQuIgogICAgICAgIHBtID0geyJhaXJwb2Rz"
    "Ijoi7JeQ7Ja07YyfIiwiYWlycG9kcyBwcm8iOiLsl5DslrTtjJ8g7ZSE66GcIiwiaXBob25lIjoi"
    "7JWE7J207Y+wIiwiZ2FsYXh5Ijoi6rCk65+t7IucIiwKICAgICAgICAgICAgICAibWFjYm9vayI6"
    "Iuunpeu2gSIsImlwYWQiOiLslYTsnbTtjKjrk5wiLCJuaW50ZW5kbyBzd2l0Y2giOiLri4zthZDr"
    "j4Qg7Iqk7JyE7LmYIiwicHM1Ijoi7ZSM66CI7J207Iqk7YWM7J207IWYNSJ9CiAgICAgICAgcmV0"
    "dXJuIGF3YWl0IHNlbGYuX25hdmVyX3NlYXJjaChzZWxmLl90cmFuc2xhdGVfa2V5d29yZChwcm9k"
    "dWN0LCBwbSkgKyAiIOqwgOqyqSIsCiAgICAgICAgICAgICJmaW5kIGxvd2VzdCBwcmljZSwgc3Rv"
    "cmUgbmFtZSwgZGVsaXZlcnkgaW5mby4gUmVzcG9uZCBpbiBLb3JlYW4uIiwgX19ldmVudF9lbWl0"
    "dGVyX18pCgogICAgYXN5bmMgZGVmIGNoZWNrX3N0b2NrKHNlbGYsIGNvbXBhbnk6IHN0ciwgX19l"
    "dmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiQ2hlY2sgc3RvY2sgcHJpY2UgYW5kIG1h"
    "cmtldCBkYXRhLgogICAgICAgIDpwYXJhbSBjb21wYW55OiBDb21wYW55IG5hbWUKICAgICAgICAi"
    "IiIKICAgICAgICBpZiBub3QgY29tcGFueS5zdHJpcCgpOiByZXR1cm4gIu2ajOyCrOuqheydhCDs"
    "noXroKXtlZjshLjsmpQuIgogICAgICAgIHNtID0geyJzYW1zdW5nIjoi7IK87ISx7KCE7J6QIiwi"
    "c2sgaHluaXgiOiJTS+2VmOydtOuLieyKpCIsImFwcGxlIjoi7JWg7ZSMIOyjvOqwgCIsIm52aWRp"
    "YSI6IuyXlOu5hOuUlOyVhCDso7zqsIAiLAogICAgICAgICAgICAgICJ0ZXNsYSI6Iu2FjOyKrOud"
    "vCDso7zqsIAiLCJrb3NwaSI6Iuy9lOyKpO2UvCIsImtvc2RhcSI6Iuy9lOyKpOuLpSIsIm5hc2Rh"
    "cSI6IuuCmOyKpOuLpSJ9CiAgICAgICAgayA9IHNlbGYuX3RyYW5zbGF0ZV9rZXl3b3JkKGNvbXBh"
    "bnksIHNtKQogICAgICAgIGlmICLso7zqsIAiIG5vdCBpbiBrIGFuZCBrIG5vdCBpbiBbIuy9lOyK"
    "pO2UvCIsIuy9lOyKpOuLpSIsIuuCmOyKpOuLpSJdOiBrICs9ICIg7KO86rCAIgogICAgICAgIHJl"
    "dHVybiBhd2FpdCBzZWxmLl9uYXZlcl9zZWFyY2goaywgInJlYWQgc3RvY2sgcHJpY2UsIGNoYW5n"
    "ZSwgbWFya2V0IGNhcC4gUmVzcG9uZCBpbiBLb3JlYW4uIiwgX19ldmVudF9lbWl0dGVyX18pCgog"
    "ICAgYXN5bmMgZGVmIGNoZWNrX25ld3Moc2VsZiwgdG9waWM6IHN0ciA9ICIiLCBfX2V2ZW50X2Vt"
    "aXR0ZXJfXz1Ob25lKToKICAgICAgICAiIiJDaGVjayB0b2RheSdzIHRvcCBuZXdzIGhlYWRsaW5l"
    "cyBmcm9tIE5hdmVyIE5ld3MuIE9wdGlvbmFsbHkgZmlsdGVyIGJ5IHRvcGljLgogICAgICAgIDpw"
    "YXJhbSB0b3BpYzog64m07IqkIOyjvOygnCAo7JiIOiDqsr3soJwsIOyKpO2PrOy4oCwgSVQsIOu2"
    "gOyCsCkuIOu5hOybjOuRkOuptCDsmKTripjsnZgg7KO87JqUIOuJtOyKpCDsoITssrQuCiAgICAg"
    "ICAgIiIiCiAgICAgICAgdHAgPSAodG9waWMgb3IgIiIpLnN0cmlwKCkKICAgICAgICBjYWNoZV9r"
    "ZXkgPSAibmV3czoiICsgKHRwIG9yICJ0b2RheSIpCiAgICAgICAgY2FjaGVkID0gc2VsZi5fZ2V0"
    "X2NhY2hlKGNhY2hlX2tleSkKICAgICAgICBpZiBjYWNoZWQ6IHJldHVybiBjYWNoZWQKICAgICAg"
    "ICBxdWVyeSA9ICh0cCArICIg64m07IqkIikgaWYgdHAgZWxzZSAi7Jik64qYIOyjvOyalCDribTs"
    "iqQiCiAgICAgICAgcmVzdWx0ID0gYXdhaXQgc2VsZi5fYXBpX3NlYXJjaChxdWVyeSwga2luZD0i"
    "bmV3cyIsIGRpc3BsYXk9NSwgX19ldmVudF9lbWl0dGVyX189X19ldmVudF9lbWl0dGVyX18pCiAg"
    "ICAgICAgc2VsZi5fc2V0X2NhY2hlKGNhY2hlX2tleSwgcmVzdWx0KQogICAgICAgIHJldHVybiBy"
    "ZXN1bHQKCiAgICBhc3luYyBkZWYgY2hlY2tfZXhjaGFuZ2VfcmF0ZShzZWxmLCBjdXJyZW5jeTog"
    "c3RyID0gImRvbGxhciIsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIkNoZWNr"
    "IGN1cnJlbnQgZXhjaGFuZ2UgcmF0ZXMuCiAgICAgICAgOnBhcmFtIGN1cnJlbmN5OiBDdXJyZW5j"
    "eSBuYW1lIChkb2xsYXIsIHllbiwgZXVybywgeXVhbikKICAgICAgICAiIiIKICAgICAgICBybSA9"
    "IHsiZG9sbGFyIjoi64us65+sIO2ZmOycqCIsInVzZCI6IuuLrOufrCDtmZjsnKgiLCJ5ZW4iOiLs"
    "l5TtmZQg7ZmY7JyoIiwiZXVybyI6IuycoOuhnCDtmZjsnKgiLCJ5dWFuIjoi7JyE7JWIIO2ZmOyc"
    "qCIsInBvdW5kIjoi7YyM7Jq065OcIO2ZmOycqCJ9CiAgICAgICAgcmV0dXJuIGF3YWl0IHNlbGYu"
    "X25hdmVyX3NlYXJjaChzZWxmLl90cmFuc2xhdGVfa2V5d29yZChjdXJyZW5jeSwgcm0pLAogICAg"
    "ICAgICAgICAicmVhZCBleGNoYW5nZSByYXRlLCBjaGFuZ2UgZnJvbSB5ZXN0ZXJkYXkuIFJlc3Bv"
    "bmQgaW4gS29yZWFuLiIsIF9fZXZlbnRfZW1pdHRlcl9fKQoKICAgIGFzeW5jIGRlZiBjaGVja19z"
    "cG9ydHMoc2VsZiwgc3BvcnQ6IHN0ciA9ICJzb2NjZXIiLCBfX2V2ZW50X2VtaXR0ZXJfXz1Ob25l"
    "KToKICAgICAgICAiIiJDaGVjayBzcG9ydHMgc2NvcmVzIGFuZCByZXN1bHRzLgogICAgICAgIDpw"
    "YXJhbSBzcG9ydDogU3BvcnQgdHlwZSAoc29jY2VyLCBiYXNlYmFsbCwgYmFza2V0YmFsbCwga2Jv"
    "LCBlcGwpCiAgICAgICAgIiIiCiAgICAgICAgc20gPSB7InNvY2NlciI6Iuy2leq1rCDqsr3quLDq"
    "srDqs7wiLCJiYXNlYmFsbCI6IuyVvOq1rCDqsr3quLDqsrDqs7wiLCJiYXNrZXRiYWxsIjoi64aN"
    "6rWsIOqyveq4sOqysOqzvCIsCiAgICAgICAgICAgICAgImtibyI6IktCTyDqsr3quLDqsrDqs7wi"
    "LCJlcGwiOiJFUEwg6rKw6rO8IiwibmJhIjoiTkJBIOqysOqzvCJ9CiAgICAgICAgcmV0dXJuIGF3"
    "YWl0IHNlbGYuX25hdmVyX3NlYXJjaChzZWxmLl90cmFuc2xhdGVfa2V5d29yZChzcG9ydCwgc20p"
    "LAogICAgICAgICAgICAicmVhZCByZWNlbnQgbWF0Y2ggcmVzdWx0cywgc2NvcmVzLCBzdGFuZGlu"
    "Z3MuIFJlc3BvbmQgaW4gS29yZWFuLiIsIF9fZXZlbnRfZW1pdHRlcl9fKQoKICAgIGFzeW5jIGRl"
    "ZiBzdW1tYXJpemVfeW91dHViZShzZWxmLCB1cmw6IHN0ciwgX19ldmVudF9lbWl0dGVyX189Tm9u"
    "ZSk6CiAgICAgICAgIiIiU3VtbWFyaXplIGEgWW91VHViZSB2aWRlby4KICAgICAgICA6cGFyYW0g"
    "dXJsOiBZb3VUdWJlIFVSTAogICAgICAgICIiIgogICAgICAgIGlmICJ5b3V0dWJlLmNvbSIgbm90"
    "IGluIHVybCBhbmQgInlvdXR1LmJlIiBub3QgaW4gdXJsOiByZXR1cm4gIllvdVR1YmUgVVJM7J20"
    "IOyVhOuLmeuLiOuLpC4iCiAgICAgICAgcmV0dXJuIGF3YWl0IHNlbGYuYnJvd3NlKHVybCArICIg"
    "c3VtbWFyaXplIHZpZGVvIHRpdGxlLCBjaGFubmVsLCB2aWV3IGNvdW50LCBtYWluIGNvbnRlbnQg"
    "aW4gS29yZWFuLiIsIF9fZXZlbnRfZW1pdHRlcl9fKQoKICAgIGFzeW5jIGRlZiBvcGVuX2FuZF9z"
    "dW1tYXJpemUoc2VsZiwgdXJsOiBzdHIsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAg"
    "ICIiIk9wZW4gYSB3ZWJwYWdlIGFuZCBzdW1tYXJpemUgaW4gS29yZWFuLgogICAgICAgIDpwYXJh"
    "bSB1cmw6IEZ1bGwgVVJMCiAgICAgICAgIiIiCiAgICAgICAgaWYgbm90IHVybC5zdGFydHN3aXRo"
    "KCgiaHR0cDovLyIsImh0dHBzOi8vIikpOiByZXR1cm4gIlVSTOydgCBodHRwOi8v66GcIOyLnOye"
    "ke2VtOyVvCDtlanri4jri6QuIgogICAgICAgIGJsb2NrZWQgPSBbImNvdXBhbmcuY29tIiwiZ21h"
    "cmtldC5jby5rciIsIjExc3QuY28ua3IiLCJhdWN0aW9uLmNvLmtyIl0KICAgICAgICBpZiBhbnko"
    "cyBpbiB1cmwubG93ZXIoKSBmb3IgcyBpbiBibG9ja2VkKTogcmV0dXJuICLsnbQg7IKs7J207Yq4"
    "64qUIOywqOuLqOuQqeuLiOuLpC4gY2hlY2tfcHJpY2Xrpbwg7IKs7Jqp7ZWY7IS47JqULiIKICAg"
    "ICAgICBpZiAieW91dHViZS5jb20iIGluIHVybCBvciAieW91dHUuYmUiIGluIHVybDogcmV0dXJu"
    "IGF3YWl0IHNlbGYuc3VtbWFyaXplX3lvdXR1YmUodXJsLCBfX2V2ZW50X2VtaXR0ZXJfXykKICAg"
    "ICAgICByZXR1cm4gYXdhaXQgc2VsZi5icm93c2UodXJsICsgIiBzdW1tYXJpemUgdGhlIG1haW4g"
    "Y29udGVudCBpbiBLb3JlYW4iLCBfX2V2ZW50X2VtaXR0ZXJfXykKCiAgICBhc3luYyBkZWYgbXVs"
    "dGlfYWdlbnRfYnJvd3NlKHNlbGYsIHRhc2s6IHN0ciwgX19ldmVudF9lbWl0dGVyX189Tm9uZSwg"
    "X191c2VyX189e30pOgogICAgICAgICIiIk11bHRpLUFnZW50IOuqqOuTnOuhnCDrs7XsnqHtlZwg"
    "7J6R7JeFIOyImO2WiS4KICAgICAgICA6cGFyYW0gdGFzazog7J6R7JeFIOuCtOyaqQogICAgICAg"
    "ICIiIgogICAgICAgIGFzeW5jIGRlZiBlbWl0KG1zZywgZG9uZT1GYWxzZSk6CiAgICAgICAgICAg"
    "IGlmIF9fZXZlbnRfZW1pdHRlcl9fOiBhd2FpdCBfX2V2ZW50X2VtaXR0ZXJfXyh7InR5cGUiOiJz"
    "dGF0dXMiLCJkYXRhIjp7ImRlc2NyaXB0aW9uIjptc2csImRvbmUiOmRvbmV9fSkKICAgICAgICBh"
    "d2FpdCBlbWl0KCJNdWx0aS1BZ2VudCDsobDsgqwg7Iuc7J6RLi4uIikKICAgICAgICB0cnk6CiAg"
    "ICAgICAgICAgIHJlc3VsdCA9IGF3YWl0IHNlbGYuX3Bvc3QoIi9icm93c2UvbXVsdGkiLCB7InRh"
    "c2siOiB0YXNrfSkKICAgICAgICAgICAgYXdhaXQgZW1pdCgi7JmE66OMIiwgZG9uZT1UcnVlKQog"
    "ICAgICAgICAgICByZXR1cm4gcmVzdWx0LmdldCgic3VtbWFyeSIsIHJlc3VsdC5nZXQoInJlc3Vs"
    "dCIsIHN0cihyZXN1bHQpKSkKICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAgICAgICAg"
    "ICAgIGF3YWl0IGVtaXQoIuyYpOulmCIsIGRvbmU9VHJ1ZSkKICAgICAgICAgICAgcmV0dXJuICJN"
    "dWx0aS1BZ2VudCDsmKTrpZg6ICIgKyBzdHIoZSkKCiAgICBhc3luYyBkZWYgY2xvc2VfYnJvd3Nl"
    "cihzZWxmLCBfX2V2ZW50X2VtaXR0ZXJfXz1Ob25lKToKICAgICAgICAiIiJDbG9zZSBicm93c2Vy"
    "IHNlc3Npb24gYW5kIGNsZWFyIGNhY2hlLiIiIgogICAgICAgIHNlbGYuX3Nlc3Npb25faWQgPSBO"
    "b25lCiAgICAgICAgc2VsZi5fY2FjaGUuY2xlYXIoKQogICAgICAgIHJldHVybiAi67iM65287Jqw"
    "7KCAIOyEuOyFmCDsooXro4wgKyDsupDsi5wg7LSI6riw7ZmUIOyZhOujjCIKCiAgICBhc3luYyBk"
    "ZWYgZ2V0X21lbW9yeShzZWxmLCBfX2V2ZW50X2VtaXR0ZXJfXz1Ob25lKToKICAgICAgICAiIiLs"
    "oIDsnqXrkJwg7IKs7Jqp7J6QIOygleuztCDsobDtmowuIiIiCiAgICAgICAgaWYgbm90IHNlbGYu"
    "dmFsdmVzLkVOQUJMRV9NRU1PUlk6IHJldHVybiAi66mU66qo66asIOu5hO2ZnOyEse2ZlCIKICAg"
    "ICAgICB0cnk6CiAgICAgICAgICAgIGltcG9ydCBodHRweCwganNvbgogICAgICAgICAgICBhc3lu"
    "YyB3aXRoIGh0dHB4LkFzeW5jQ2xpZW50KHRpbWVvdXQ9MTApIGFzIGM6CiAgICAgICAgICAgICAg"
    "ICByID0gYXdhaXQgYy5nZXQoc2VsZi52YWx2ZXMuQlJPV1NFUl9BR0VOVF9VUkwgKyAiL21lbW9y"
    "eSIsIGhlYWRlcnM9c2VsZi5faGVhZGVycygpKQogICAgICAgICAgICAgICAgcmV0dXJuICLwn5Od"
    "IOuplOuqqOumrDpcbiIgKyBqc29uLmR1bXBzKHIuanNvbigpLCBlbnN1cmVfYXNjaWk9RmFsc2Us"
    "IGluZGVudD0yKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZTogcmV0dXJuICLrqZTrqqjr"
    "pqwg7KGw7ZqMIOyLpO2MqDogIiArIHN0cihlKQoKICAgIGFzeW5jIGRlZiB1cGRhdGVfbWVtb3J5"
    "KHNlbGYsIGluZm86IHN0ciwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIi7IKs"
    "7Jqp7J6QIOygleuztCDsoIDsnqUuCiAgICAgICAgOnBhcmFtIGluZm86IOq4sOyWte2VoCDsoJXr"
    "s7QKICAgICAgICAiIiIKICAgICAgICBpZiBub3Qgc2VsZi52YWx2ZXMuRU5BQkxFX01FTU9SWTog"
    "cmV0dXJuICLrqZTrqqjrpqwg67mE7Zmc7ISx7ZmUIgogICAgICAgIGJvZHkgPSB7ImZhY3RzIjog"
    "W2luZm9bOjIwMF1dfQogICAgICAgIGZvciBsb2MgaW4gWyLshJzsmrgiLCLrtoDsgrAiLCLrjIDq"
    "tawiLCLsnbjsspwiLCLqtJHso7wiLCLrjIDsoIQiLCLsmrjsgrAiLCLsoJzso7wiXToKICAgICAg"
    "ICAgICAgaWYgbG9jIGluIGluZm86IGJvZHlbImxvY2F0aW9uIl0gPSBsb2M7IGJyZWFrCiAgICAg"
    "ICAgdHJ5OgogICAgICAgICAgICBhd2FpdCBzZWxmLl9wb3N0KCIvbWVtb3J5IiwgYm9keSk7IHJl"
    "dHVybiAi4pyFIOq4sOyWte2WiOyKteuLiOuLpDogIiArIGluZm8KICAgICAgICBleGNlcHQgRXhj"
    "ZXB0aW9uIGFzIGU6IHJldHVybiAi7KCA7J6lIOyLpO2MqDogIiArIHN0cihlKQoKICAgIGFzeW5j"
    "IGRlZiBjbGVhcl9tZW1vcnkoc2VsZiwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAg"
    "IiIi7KCA7J6l65CcIOuqqOuToCDrqZTrqqjrpqwg7IKt7KCcLiIiIgogICAgICAgIHRyeToKICAg"
    "ICAgICAgICAgaW1wb3J0IGh0dHB4CiAgICAgICAgICAgIGFzeW5jIHdpdGggaHR0cHguQXN5bmND"
    "bGllbnQodGltZW91dD0xMCkgYXMgYzoKICAgICAgICAgICAgICAgIGF3YWl0IGMuZGVsZXRlKHNl"
    "bGYudmFsdmVzLkJST1dTRVJfQUdFTlRfVVJMICsgIi9tZW1vcnkiLCBoZWFkZXJzPXNlbGYuX2hl"
    "YWRlcnMoKSkKICAgICAgICAgICAgICAgIHJldHVybiAi4pyFIOuplOuqqOumrCDstIjquLDtmZQg"
    "7JmE66OMIgogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZTogcmV0dXJuICLsgq3soJwg7Iuk"
    "7YyoOiAiICsgc3RyKGUpCgogICAgYXN5bmMgZGVmIGxpc3RfZmlsZXMoc2VsZiwgX19ldmVudF9l"
    "bWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIifi9haS1zaGFyZSDtj7TrjZTsnZgg7YyM7J28IOuq"
    "qeuhnSDsobDtmowuIiIiCiAgICAgICAgaWYgbm90IHNlbGYudmFsdmVzLkVOQUJMRV9GSUxFX0FD"
    "Q0VTUzogcmV0dXJuICLtjIzsnbwg7KCR6re8IOu5hO2ZnOyEse2ZlCIKICAgICAgICB0cnk6CiAg"
    "ICAgICAgICAgIGltcG9ydCBodHRweAogICAgICAgICAgICBhc3luYyB3aXRoIGh0dHB4LkFzeW5j"
    "Q2xpZW50KHRpbWVvdXQ9MTApIGFzIGM6CiAgICAgICAgICAgICAgICByID0gYXdhaXQgYy5nZXQo"
    "c2VsZi52YWx2ZXMuQlJPV1NFUl9BR0VOVF9VUkwgKyAiL2ZpbGVzIiwgaGVhZGVycz1zZWxmLl9o"
    "ZWFkZXJzKCkpCiAgICAgICAgICAgICAgICBmaWxlcyA9IHIuanNvbigpLmdldCgiZmlsZXMiLCBb"
    "XSkKICAgICAgICAgICAgICAgIGlmIG5vdCBmaWxlczogcmV0dXJuICLwn5OBIO2MjOydvCDsl4bs"
    "nYwgKH4vYWktc2hhcmXsl5Ag7YyM7J287J2EIOuEo+yWtOyjvOyEuOyalCkiCiAgICAgICAgICAg"
    "ICAgICBsaW5lcyA9IFsi8J+TgSDtjIzsnbwg66qp66GdOiJdCiAgICAgICAgICAgICAgICBmb3Ig"
    "ZiBpbiBmaWxlczoKICAgICAgICAgICAgICAgICAgICBsaW5lcy5hcHBlbmQoIiAg4oCiICIgKyBm"
    "WyJuYW1lIl0gKyAiICgiICsgc3RyKHJvdW5kKGZbInNpemUiXS8xMDI0LCAxKSkgKyAiS0IpIikK"
    "ICAgICAgICAgICAgICAgIHJldHVybiAiXG4iLmpvaW4obGluZXMpCiAgICAgICAgZXhjZXB0IEV4"
    "Y2VwdGlvbiBhcyBlOiByZXR1cm4gIuyhsO2ajCDsi6TtjKg6ICIgKyBzdHIoZSkKCiAgICBhc3lu"
    "YyBkZWYgcmVhZF9maWxlKHNlbGYsIGZpbGVuYW1lOiBzdHIsIF9fZXZlbnRfZW1pdHRlcl9fPU5v"
    "bmUpOgogICAgICAgICIiIuuhnOy7rCDtjIzsnbwg7J296riwLgogICAgICAgIDpwYXJhbSBmaWxl"
    "bmFtZTog7YyM7J2866qFCiAgICAgICAgIiIiCiAgICAgICAgaWYgbm90IHNlbGYudmFsdmVzLkVO"
    "QUJMRV9GSUxFX0FDQ0VTUzogcmV0dXJuICLtjIzsnbwg7KCR6re8IOu5hO2ZnOyEse2ZlCIKICAg"
    "ICAgICB0cnk6CiAgICAgICAgICAgIGltcG9ydCBodHRweAogICAgICAgICAgICBhc3luYyB3aXRo"
    "IGh0dHB4LkFzeW5jQ2xpZW50KHRpbWVvdXQ9MzApIGFzIGM6CiAgICAgICAgICAgICAgICByID0g"
    "YXdhaXQgYy5nZXQoc2VsZi52YWx2ZXMuQlJPV1NFUl9BR0VOVF9VUkwgKyAiL2ZpbGVzLyIgKyBm"
    "aWxlbmFtZSwgaGVhZGVycz1zZWxmLl9oZWFkZXJzKCkpCiAgICAgICAgICAgICAgICBpZiByLnN0"
    "YXR1c19jb2RlID09IDQwNDogcmV0dXJuICLinYwg7YyM7J28IOyXhuydjDogIiArIGZpbGVuYW1l"
    "CiAgICAgICAgICAgICAgICByZXR1cm4gIvCfk4QgIiArIGZpbGVuYW1lICsgIjpcbiIgKyByLmpz"
    "b24oKS5nZXQoImNvbnRlbnQiLCAiIilbOjUwMDBdCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBh"
    "cyBlOiByZXR1cm4gIuydveq4sCDsi6TtjKg6ICIgKyBzdHIoZSkKCiAgICBhc3luYyBkZWYgc2F2"
    "ZV9maWxlKHNlbGYsIGZpbGVuYW1lOiBzdHIsIGNvbnRlbnQ6IHN0ciwgX19ldmVudF9lbWl0dGVy"
    "X189Tm9uZSk6CiAgICAgICAgIiIi66Gc7LusIO2MjOydvCDsoIDsnqUuCiAgICAgICAgOnBhcmFt"
    "IGZpbGVuYW1lOiDtjIzsnbzrqoUKICAgICAgICA6cGFyYW0gY29udGVudDog7KCA7J6l7ZWgIOuC"
    "tOyaqQogICAgICAgICIiIgogICAgICAgIGlmIG5vdCBzZWxmLnZhbHZlcy5FTkFCTEVfRklMRV9B"
    "Q0NFU1M6IHJldHVybiAi7YyM7J28IOygkeq3vCDruYTtmZzshLHtmZQiCiAgICAgICAgdHJ5Ogog"
    "ICAgICAgICAgICBpbXBvcnQgaHR0cHgKICAgICAgICAgICAgYXN5bmMgd2l0aCBodHRweC5Bc3lu"
    "Y0NsaWVudCh0aW1lb3V0PTMwKSBhcyBjOgogICAgICAgICAgICAgICAgciA9IGF3YWl0IGMucG9z"
    "dChzZWxmLnZhbHZlcy5CUk9XU0VSX0FHRU5UX1VSTCArICIvZmlsZXMvIiArIGZpbGVuYW1lLCBq"
    "c29uPXsiY29udGVudCI6Y29udGVudH0sIGhlYWRlcnM9c2VsZi5faGVhZGVycygpKQogICAgICAg"
    "ICAgICAgICAgZCA9IHIuanNvbigpCiAgICAgICAgICAgICAgICBpZiBkLmdldCgic3VjY2VzcyIp"
    "OiByZXR1cm4gIuKchSDsoIDsnqU6ICIgKyBmaWxlbmFtZSArICIgKCIgKyBzdHIoZC5nZXQoInNp"
    "emUiLDApKSArICJCKSIKICAgICAgICAgICAgICAgIHJldHVybiAi4p2MIOyLpO2MqDogIiArIHN0"
    "cihkKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZTogcmV0dXJuICLsoIDsnqUg7Iuk7Yyo"
    "OiAiICsgc3RyKGUpCgogICAgYXN5bmMgZGVmIGNvbXBhcmVfc2l0ZXMoc2VsZiwgdGFzazogc3Ry"
    "LCB1cmxzOiBzdHIgPSAiIiwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIi7Jes"
    "65+sIOyCrOydtO2KuCDruYTqtZAg67aE7ISdICjsnKDro4wgQVBJIOq2jOyepSkuCiAgICAgICAg"
    "OnBhcmFtIHRhc2s6IOu5hOq1kCDrgrTsmqkKICAgICAgICA6cGFyYW0gdXJsczogVVJM65OkIOyJ"
    "vO2RnCDqtazrtoQgKOu5hOybjOuRkOuptCDsnpDrj5kpCiAgICAgICAgIiIiCiAgICAgICAgaWYg"
    "bm90IHNlbGYudmFsdmVzLkVOQUJMRV9NVUxUSVRBQjogcmV0dXJuICLrqYDti7Dtg60g67mE7Zmc"
    "7ISx7ZmUIgogICAgICAgIGlmIF9fZXZlbnRfZW1pdHRlcl9fOiBhd2FpdCBfX2V2ZW50X2VtaXR0"
    "ZXJfXyh7InR5cGUiOiJzdGF0dXMiLCJkYXRhIjp7ImRlc2NyaXB0aW9uIjoi66mA7Yuw7YOtIOu5"
    "hOq1kCDsi5zsnpEuLi4iLCJkb25lIjpGYWxzZX19KQogICAgICAgIHVybF9saXN0ID0gW3Uuc3Ry"
    "aXAoKSBmb3IgdSBpbiB1cmxzLnNwbGl0KCIsIikgaWYgdS5zdHJpcCgpXVs6c2VsZi52YWx2ZXMu"
    "TUFYX1RBQlNdIGlmIHVybHMgZWxzZSBbXQogICAgICAgIHRyeToKICAgICAgICAgICAgaW1wb3J0"
    "IGh0dHB4CiAgICAgICAgICAgIGJvZHkgPSB7InRhc2siOnRhc2ssInVybHMiOnVybF9saXN0LCJt"
    "YXhfc3RlcHNfcGVyX3RhYiI6OH0KICAgICAgICAgICAgaWYgc2VsZi52YWx2ZXMuTExNX1BST1ZJ"
    "REVSOiBib2R5WyJwcm92aWRlciJdID0gc2VsZi52YWx2ZXMuTExNX1BST1ZJREVSCiAgICAgICAg"
    "ICAgIGlmIHNlbGYudmFsdmVzLkxMTV9BUElfS0VZOiBib2R5WyJhcGlfa2V5Il0gPSBzZWxmLnZh"
    "bHZlcy5MTE1fQVBJX0tFWQogICAgICAgICAgICBpZiBzZWxmLnZhbHZlcy5MTE1fTU9ERUw6IGJv"
    "ZHlbIm1vZGVsIl0gPSBzZWxmLnZhbHZlcy5MTE1fTU9ERUwKICAgICAgICAgICAgYXN5bmMgd2l0"
    "aCBodHRweC5Bc3luY0NsaWVudCh0aW1lb3V0PXNlbGYudmFsdmVzLlJFUVVFU1RfVElNRU9VVCkg"
    "YXMgYzoKICAgICAgICAgICAgICAgIHIgPSBhd2FpdCBjLnBvc3Qoc2VsZi52YWx2ZXMuQlJPV1NF"
    "Ul9BR0VOVF9VUkwgKyAiL2Jyb3dzZS9tdWx0aXRhYiIsIGpzb249Ym9keSwgaGVhZGVycz1zZWxm"
    "Ll9oZWFkZXJzKCkpCiAgICAgICAgICAgICAgICBkYXRhID0gci5qc29uKCkKICAgICAgICAgICAg"
    "aWYgX19ldmVudF9lbWl0dGVyX186IGF3YWl0IF9fZXZlbnRfZW1pdHRlcl9fKHsidHlwZSI6InN0"
    "YXR1cyIsImRhdGEiOnsiZGVzY3JpcHRpb24iOiLsmYTro4wiLCJkb25lIjpUcnVlfX0pCiAgICAg"
    "ICAgICAgIGlmIGRhdGEuZ2V0KCJzdWNjZXNzIik6CiAgICAgICAgICAgICAgICB0YWJzID0gZGF0"
    "YS5nZXQoInRhYnMiLFtdKQogICAgICAgICAgICAgICAgc291cmNlcyA9ICJcbiIuam9pbihbIiAg"
    "4oCiIO2DrSIgKyBzdHIodFsidGFiIl0pICsgIjogIiArIHRbInVybCJdIGZvciB0IGluIHRhYnNd"
    "KQogICAgICAgICAgICAgICAgcmV0dXJuIGRhdGEuZ2V0KCJzdW1tYXJ5IiwiIikgKyAiXG5cbvCf"
    "k5Eg7LC47KGwOlxuIiArIHNvdXJjZXMKICAgICAgICAgICAgcmV0dXJuICLsi6TtjKg6ICIgKyBk"
    "YXRhLmdldCgiZXJyb3IiLCIiKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAg"
    "ICAgICAgaWYgX19ldmVudF9lbWl0dGVyX186IGF3YWl0IF9fZXZlbnRfZW1pdHRlcl9fKHsidHlw"
    "ZSI6InN0YXR1cyIsImRhdGEiOnsiZGVzY3JpcHRpb24iOiLsi6TtjKgiLCJkb25lIjpUcnVlfX0p"
    "CiAgICAgICAgICAgIHJldHVybiAi66mA7Yuw7YOtIOyYpOulmDogIiArIHN0cihlKQo="
)
dest = os.environ.get('AGENT_DIR','') + '/openwebui_tool.py'
with open(dest, 'w', encoding='utf-8') as f:
    f.write(base64.b64decode(b64).decode('utf-8'))
print('  ✅ openwebui_tool.py 생성 완료')
WRITE_TOOL
ok "FILE 5/6  openwebui_tool.py"

############################################
# 5-1. openwebui_tool.py 검색 경로 패치
# 검색 소스: 네이버 Search API ONLY
# 기존 search_wikipedia() 이름은 호환성을 위해 유지
############################################
step "5-1/9  네이버 Search API 전용 검색 경로 패치"

python3 - "${AGENT_DIR}" << 'WIKI_PATCH'
import re, sys

tool_path = sys.argv[1] + '/openwebui_tool.py'
try:
    with open(tool_path, 'r', encoding='utf-8') as f:
        code = f.read()
except FileNotFoundError:
    print(f"  ❌ 파일 없음: {tool_path}")
    sys.exit(1)

# ── 패치 2: _is_encyclopedic_query() 헬퍼 추가 ──────────────────────────
# 검색 경로는 항상 네이버 Search API만 사용합니다.
WIKI_HELPER = '''    def _is_encyclopedic_query(self, text: str) -> bool:
        """백과사전형 질문 감지 — 검색 자체는 항상 네이버 Search API만 사용"""
        patterns = [
            "이란", "이란?", "이란 무엇", "뜻", "정의", "개념", "역사",
            "유래", "원인", "설명", "무엇", "누구", "어떤", "어떻게",
            "what is", "who is", "history of", "definition of", "explain",
            "인물", "국가", "나라", "지역", "도시", "사건", "전쟁",
            "과학", "수학", "철학", "문학", "예술", "음악", "영화 역사",
            "위키", "백과",
        ]
        text_lower = text.lower()
        return any(p in text_lower for p in patterns)

    async def _smart_search(self, query: str, instruction: str, __event_emitter__=None):
        """스마트 검색: 모든 검색 요청을 네이버 Search API로 처리"""
        cached = self._get_cache("smart:" + query)
        if cached: return cached
        result = await self._naver_search(query, instruction, __event_emitter__)
        self._set_cache("smart:" + query, result)
        return result
'''

TARGET = '    def _translate_keyword(self, keyword: str, keyword_map: dict) -> str:'
if TARGET in code:
    code = code.replace(TARGET, WIKI_HELPER + TARGET)
    print("  ✅ 패치 2: _is_encyclopedic_query() + _smart_search() → 네이버 Search API 전용")
else:
    print("  ⚠️  패치 2: _translate_keyword 위치 불일치 — 수동 확인 필요")

# ── 패치 3: search_wikipedia() 호환 Tool ───────────────────────────────
# 이름은 기존 호환성을 위해 유지하지만 실제 검색은 네이버 Search API만 사용합니다.
WIKI_TOOL = '''
    async def search_wikipedia(self, keyword: str, __event_emitter__=None):
        """호환용 도구. 실제 검색은 네이버 Search API만 사용합니다."""
        if not keyword.strip(): return "검색어를 입력하세요."
        cached = self._get_cache("wiki:" + keyword)
        if cached: return cached
        if __event_emitter__:
            await __event_emitter__({"type": "status", "data": {"description": "🔎 네이버 Search API 검색 중...", "done": False}})
        result = await self._naver_search(keyword,
            "백과사전형 정보를 찾아 한국어로 요약하세요. 네이버 Search API 결과만 사용하세요.", __event_emitter__)
        self._set_cache("wiki:" + keyword, result)
        if __event_emitter__:
            await __event_emitter__({"type": "status", "data": {"description": "완료", "done": True}})
        return result
'''

INSERT_AFTER = '            "read the key information from search results in Korean", __event_emitter__)\n'
if INSERT_AFTER in code:
    code = code.replace(INSERT_AFTER, INSERT_AFTER + WIKI_TOOL, 1)
    print("  ✅ 패치 3: search_wikipedia() → 네이버 Search API 전용")
else:
    print("  ⚠️  패치 3: search_naver 삽입 위치 불일치 — 수동 확인 필요")

# ── 패치 4: Valves에 WIKIPEDIA_PRIORITY 옵션 추가 ─────────────────────────
OLD_VALVE_END = '        LLM_MODEL: str = Field(default="", description="모델명 (비워두면 기본값)")'
NEW_VALVE_END = '''        LLM_MODEL: str = Field(default="", description="모델명 (비워두면 기본값)")
        WIKIPEDIA_PRIORITY: bool = Field(default=False, description="호환용 필드 — 검색은 항상 네이버 Search API만 사용")
        WIKIPEDIA_LANG: str = Field(default="ko", description="호환용 필드 — 실제 검색 소스는 네이버 Search API")'''

if OLD_VALVE_END in code:
    code = code.replace(OLD_VALVE_END, NEW_VALVE_END)
    print("  ✅ 패치 4: Valves에 WIKIPEDIA_PRIORITY 옵션 추가됨")
else:
    print("  ⚠️  패치 4: Valves 위치 불일치")

# ── 저장 ─────────────────────────────────────────────────────────────────
with open(tool_path, 'w', encoding='utf-8') as f:
    f.write(code)

# Tool 함수 목록 확인
tool_fns = re.findall(r'    async def ([a-z_]+)\(', code)
print(f"\n  📋 최종 Tool 목록 ({len(tool_fns)}개):")
for fn in tool_fns:
    print(f"      • {fn}()")
print("\n  ✅ 위키피디아 패치 완료!")
WIKI_PATCH

ok "위키피디아 검색 패치 완료"
echo ""
info "검색 우선순위:"
info "  실시간 정보: 네이버 Search API"
info "  백과사전형 : 네이버 Search API"
info "호환 Tool   : search_wikipedia(keyword) → 네이버 Search API"

############################################
# 5-2. openwebui_tool.py 신규 Tool 3개
# ⑩ 지도검색  ⑪ 파일다운로드  ⑫ Excel/CSV 내보내기
############################################
step "5-2/9  Tool 업그레이드 — 신규 3개 Tool"

python3 - "${AGENT_DIR}" << 'TOOL_UPGRADE'
import os, re, sys

tool_path = sys.argv[1] + '/openwebui_tool.py'
try:
    with open(tool_path, encoding='utf-8') as f: code = f.read()
except FileNotFoundError:
    print(f"  ❌ 파일 없음: {tool_path}"); sys.exit(1)

ok_list = []

NEW_TOOLS = """
    async def take_screenshot(self, url: str, full_page: bool = False, __event_emitter__=None):
        \"\"\"웹 페이지 스크린샷 캡처. '이 사이트 캡처해줘' / '화면 저장해줘'.
        :param url: 캡처할 페이지 URL
        :param full_page: True=전체 페이지, False=화면 영역만 (기본)
        \"\"\"
        if not url.strip(): return "URL을 입력하세요."
        async def emit(msg, done=False):
            if __event_emitter__:
                await __event_emitter__({"type":"status","data":{"description":msg,"done":done}})
        await emit(f"📸 스크린샷 캡처 중: {url[:50]}...")
        result = await self._call_api("/screenshot", {"url": url, "full_page": full_page})
        if isinstance(result, dict) and "screenshot_b64" in result:
            b64 = result["screenshot_b64"]
            size = result.get("size_bytes", 0) // 1024
            await emit("✅ 완료", done=True)
            return (f"![스크린샷](data:image/jpeg;base64,{b64})\\n\\n"
                    f"📸 URL: {url}\\n크기: {size}KB")
        await emit("완료", done=True)
        return str(result)

    async def search_map(self, keyword: str, service: str = "naver", __event_emitter__=None):
        \"\"\"카카오맵 또는 네이버지도에서 위치 정보 검색.
        '강남역 맛집 찾아줘' / '서울시청 위치' / '근처 카페 검색'.
        :param keyword: 검색 키워드 (예: 강남역 맛집)
        :param service: 'naver' 또는 'kakao' (기본: naver)
        \"\"\"
        if not keyword.strip(): return "검색어를 입력하세요."
        import urllib.parse as _up
        enc = _up.quote(keyword)
        async def emit(msg, done=False):
            if __event_emitter__:
                await __event_emitter__({"type":"status","data":{"description":msg,"done":done}})
        if service.lower() == "kakao":
            map_url = f"https://map.kakao.com/?q={enc}"
        else:
            map_url = f"https://map.naver.com/v5/search/{enc}"
        cached = self._get_cache(f"map:{service}:{keyword}")
        if cached: await emit("✅ 완료(캐시)", done=True); return cached
        await emit(f"🗺️ {service} 지도 검색: {keyword}")
        task = (f"이 지도 URL에서 '{keyword}' 검색 결과 상위 3~5곳의 "
                f"이름, 주소, 영업시간, 별점을 한국어로 정리해줘: {map_url}")
        result = await self._naver_search(keyword, task, __event_emitter__)
        self._set_cache(f"map:{service}:{keyword}", result)
        await emit("✅ 완료", done=True)
        return result

    async def download_file(self, url: str, filename: str = "", __event_emitter__=None):
        \"\"\"웹에서 파일(PDF·이미지·문서 등)을 ~/ai-share 에 다운로드.
        '이 파일 저장해줘' / 'PDF 다운로드해줘'.
        :param url: 다운로드할 파일 URL
        :param filename: 저장 파일명 (비워두면 URL에서 자동 추출)
        \"\"\"
        if not url.strip(): return "다운로드할 URL을 입력하세요."
        import urllib.parse as _up, os as _os
        async def emit(msg, done=False):
            if __event_emitter__:
                await __event_emitter__({"type":"status","data":{"description":msg,"done":done}})
        if not filename:
            filename = _up.urlparse(url).path.split("/")[-1] or "downloaded_file"
            filename = _os.path.basename(filename)[:100]
        safe = __import__('re').sub(r'[^a-zA-Z0-9가-힣._-]', '_', filename)
        await emit(f"⬇️ 다운로드 중: {url[:60]}...")
        task = (f"이 URL의 파일을 다운로드해서 /app/data/user_files/{safe} 에 저장해줘: {url}\\n"
                "저장 완료 후 파일 크기와 경로를 알려줘.")
        result = await self.browse(task, __event_emitter__)
        await emit("✅ 완료", done=True)
        return result

    async def export_to_excel(self, task: str, filename: str = "result.xlsx",
                              __event_emitter__=None):
        \"\"\"웹 데이터를 수집해서 Excel 또는 CSV 파일로 저장.
        '삼성전자 주가 엑셀로 저장해줘' / '결과를 CSV로 내보내줘'.
        :param task: 수집할 데이터 설명 (예: 코스피 상위 10종목 주가)
        :param filename: 파일명 (.xlsx 또는 .csv)
        \"\"\"
        if not task.strip(): return "수집할 데이터를 설명해주세요."
        async def emit(msg, done=False):
            if __event_emitter__:
                await __event_emitter__({"type":"status","data":{"description":msg,"done":done}})
        ext  = "csv" if filename.lower().endswith(".csv") else "xlsx"
        safe = __import__('re').sub(r'[^a-zA-Z0-9가-힣._-]', '_', filename)[:80]
        await emit(f"📊 데이터 수집 및 {ext.upper()} 변환 중...")
        if ext == "xlsx":
            save_inst = f"openpyxl로 xlsx 형식으로 /app/data/user_files/{safe} 에 저장해줘."
        else:
            save_inst = f"csv 모듈로 /app/data/user_files/{safe} 에 저장해줘."
        full_task = (f"{task}\\n수집 데이터를 표(헤더+데이터행) 형식으로 정리 후 {save_inst}\\n"
                     "저장 후 파일 경로와 행 수를 알려줘.")
        result = await self.browse(full_task, __event_emitter__)
        await emit("✅ 완료", done=True)
        return result

    async def monitor_price(self, url: str, keyword: str, target_value: str = "",
                            interval_minutes: int = 60, __event_emitter__=None, __user__: dict = {}):
        \"\"\"상품 가격·재고·지표 모니터링 등록. '5만원 되면 알려줘' / '재고 생기면 알림'.
        :param url: 모니터링할 웹 페이지 URL
        :param keyword: 감지 항목 (예: 가격, 재고, 환율)
        :param target_value: 목표값 (예: 50000) — 포함 시 트리거. 비워두면 변동만 기록.
        :param interval_minutes: 확인 주기 (분, 5~1440, 기본 60)
        \"\"\"
        if getattr(self.valves, "MONITOR_ADMIN_ONLY", True):
            role = ""
            if isinstance(__user__, dict):
                role = (__user__.get("role") or "")
            if role != "admin":
                return "가격 모니터링 등록은 관리자만 사용할 수 있습니다. (SMS 요금 보호)"
        if not url.strip() or not keyword.strip():
            return "URL과 키워드를 모두 입력하세요."
        async def emit(msg, done=False):
            if __event_emitter__:
                await __event_emitter__({"type":"status","data":{"description":msg,"done":done}})
        await emit(f"🔔 모니터링 등록: {keyword}")
        payload = {"url": url, "keyword": keyword, "target_value": target_value,
                   "label": keyword[:20],
                   "interval_minutes": max(5, min(1440, interval_minutes)),
                   "sms_to": (self.valves.SMS_NOTIFY_TO or "").strip()}
        result = await self._call_api("/monitors", payload)
        if isinstance(result, dict) and "id" in result:
            mid = result["id"]
            await emit("✅ 등록 완료", done=True)
            msg = (f"✅ 모니터링 등록 완료\\n"
                   f"🆔 ID: `{mid}`\\n🔍 항목: {keyword}\\n"
                   f"🌐 URL: {url[:60]}\\n⏱️ 주기: {interval_minutes}분")
            if target_value: msg += f"\\n🎯 목표값: {target_value}"
            return msg
        await emit("완료", done=True)
        return str(result)

    async def check_monitors(self, __event_emitter__=None):
        \"\"\"등록된 모니터링 목록과 현재 상태를 조회합니다.\"\"\"
        async def emit(msg, done=False):
            if __event_emitter__:
                await __event_emitter__({"type":"status","data":{"description":msg,"done":done}})
        await emit("📋 모니터 목록 조회 중...")
        result = await self._call_api("/monitors", {}, method="GET")
        await emit("✅ 완료", done=True)
        if isinstance(result, dict):
            mons = result.get("monitors", [])
            if not mons: return "등록된 모니터가 없습니다.\\n`monitor_price(url, keyword)`로 등록하세요."
            lines = [f"📋 모니터링 목록 ({len(mons)}개)\\n"]
            for m in mons:
                st = "🔴 트리거됨" if m.get("triggered") else "🟢 감시 중"
                lines.append(f"{st} **{m.get('label','?')}** (`{m.get('id','')}`)\\n"
                             f"  주기: {m.get('interval_minutes',60)}분 | "
                             f"마지막: {m.get('last_checked','미확인')}\\n"
                             f"  현재값: {m.get('last_value','확인 전')[:80]}")
            return "\\n\\n".join(lines)
        return str(result)

"""

INSERT_BEFORE = '    async def close_browser('
if INSERT_BEFORE in code:
    code = code.replace(INSERT_BEFORE, NEW_TOOLS + INSERT_BEFORE)
    ok_list.append('Tool 6개 추가 (스크린샷/지도/다운로드/엑셀/모니터링/모니터목록)')
else:
    print("  ⚠️  close_browser 위치 불일치")

# [FIX] _call_api 메서드 신규 정의 — 새 Tool(스크린샷/모니터링)이 의존하지만
#       base 에는 _post 만 존재. POST/GET 모두 지원하는 _call_api 를 _post 옆에 삽입.
if "async def _call_api" not in code:
    CALL_API_DEF = '''    async def _call_api(self, endpoint, data=None, method="POST"):
        import httpx
        url = self.valves.BROWSER_AGENT_URL.rstrip("/") + endpoint
        async with httpx.AsyncClient(timeout=self.valves.REQUEST_TIMEOUT) as c:
            if method.upper() == "GET":
                r = await c.get(url, headers=self._headers())
            else:
                r = await c.post(url, json=(data or {}), headers=self._headers())
            if r.status_code == 401: raise PermissionError("API 키 인증 실패")
            if r.status_code == 403: raise PermissionError("접근 거부")
            if r.status_code == 429: raise RuntimeError("요청 한도 초과")
            r.raise_for_status()
            return r.json()

    async def _post(self, path, payload):'''
    if "    async def _post(self, path, payload):" in code:
        code = code.replace("    async def _post(self, path, payload):", CALL_API_DEF, 1)
        ok_list.append("_call_api 메서드 신규 정의 (POST/GET)")
    else:
        print("  ⚠️  _post 위치 불일치 — _call_api 삽입 실패")
else:
    ok_list.append("_call_api 이미 존재")

with open(tool_path, 'w', encoding='utf-8') as f: f.write(code)
print(f"  📋 적용: {len(ok_list)}개")
for p in ok_list: print(f"    ✅ {p}")
print(f"  📋 최종 라인: {len(code.splitlines())}")
TOOL_UPGRADE

ok "openwebui_tool.py 업그레이드 완료"
info "신규 Tool: take_screenshot / search_map / download_file / export_to_excel / monitor_price / check_monitors"

############################################
# 5-2-cal. openwebui_tool.py 캘린더 (오늘 일정) Tool 추가
#   제작자: <webmaster@vulva.sex>
#   - Valves 에 OPENWEBUI_API_KEY / OPENWEBUI_URL / ADMIN_ONLY 추가
#   - get_today_schedule 메서드 추가 (밸브 키로 OpenWebUI 캘린더 조회)
############################################
step "5-2-cal/9  Tool 업그레이드 — 캘린더 (오늘 일정)"

python3 - "${AGENT_DIR}" << 'CAL_UPGRADE'
import os, sys

tool_path = sys.argv[1] + '/openwebui_tool.py'
try:
    with open(tool_path, encoding='utf-8') as f:
        code = f.read()
except FileNotFoundError:
    print(f"  ❌ 파일 없음: {tool_path}"); sys.exit(1)

ok_list = []

# ── 1) Valves 에 캘린더 필드 추가 ──
# BROWSER_AGENT_URL 필드 정의 줄 바로 뒤에 캘린더 밸브 3개 삽입
CAL_VALVES = '''        BROWSER_AGENT_URL: str = Field(default="http://browser-agent:8001", description="Browser Agent 서버 URL")
        OPENWEBUI_API_KEY: str = Field(default="", description="OpenWebUI API 키 (캘린더 조회용, sk- 또는 토큰)")
        OPENWEBUI_URL: str = Field(default="http://open-webui:8080", description="OpenWebUI 내부 주소 (캘린더 조회용)")
        CALENDAR_ADMIN_ONLY: bool = Field(default=True, description="캘린더는 관리자만 사용 (권장)")
        TWILIO_BOT_URL: str = Field(default="http://twilio-bot:5000", description="전화 봇 URL (일정 알림을 전화·문자로 받으려면 필요)")
        TWILIO_BOT_SECRET: str = Field(default="", description="전화 봇 API Secret (.env 의 API_SECRET). 비우면 알림 전화·문자 예약 건너뜀")
        ENABLE_CALL_SMS_REMINDER: bool = Field(default=True, description="일정 등록 시 알림 시각에 관리자에게 전화+문자 알림 예약 여부 (켜기/끄기)")'''

anchor = '        BROWSER_AGENT_URL: str = Field(default="http://browser-agent:8001", description="Browser Agent 서버 URL")'
if "OPENWEBUI_API_KEY" in code:
    ok_list.append("캘린더 밸브 이미 존재")
elif anchor in code:
    code = code.replace(anchor, CAL_VALVES, 1)
    ok_list.append("Valves 에 캘린더 필드 3개 추가")
else:
    print("  ⚠️  BROWSER_AGENT_URL 밸브 앵커 불일치 — 캘린더 밸브 삽입 실패")

# ── 2) get_today_schedule 메서드 추가 ──
# _headers 메서드 정의 앞에 삽입 (안정적 앵커)
CAL_METHOD = '''    async def get_schedule(self, date: str = "", days: int = 1, __user__: dict = {}) -> str:
        \"\"\"특정 날짜 또는 기간의 일정을 OpenWebUI 캘린더에서 조회합니다.
        '7월 20일 일정', '내일 일정', '이번 주 일정', '다음 주 약속' 등에 사용.
        :param date: 조회 시작 날짜 YYYY-MM-DD (예: 2026-07-20). 비우면 오늘.
        :param days: 조회할 일수 (1=하루, 7=일주일). 기본 1.
        \"\"\"
        import datetime as _dt
        import httpx as _httpx
        if self.valves.CALENDAR_ADMIN_ONLY:
            role = ""
            if isinstance(__user__, dict):
                role = (__user__.get("role") or "")
            if role != "admin":
                return "이 기능은 관리자만 사용할 수 있습니다."
        key = (self.valves.OPENWEBUI_API_KEY or "").strip()
        if not key:
            return "캘린더 도구 설정(밸브)에 OpenWebUI API 키를 먼저 입력해 주세요."
        url = (self.valves.OPENWEBUI_URL or "http://open-webui:8080").rstrip("/")
        d = (date or "").strip()
        if d:
            try:
                base = _dt.date.fromisoformat(d)
            except ValueError:
                return f"날짜 형식을 이해하지 못했습니다: {date} (예: 2026-07-20)"
        else:
            base = _dt.date.today()
        try:
            span = int(days)
        except (TypeError, ValueError):
            span = 1
        span = max(1, min(span, 31))
        start_iso = f"{base.isoformat()}T00:00:00"
        end_iso = f"{(base + _dt.timedelta(days=span)).isoformat()}T00:00:00"
        try:
            async with _httpx.AsyncClient(timeout=15, follow_redirects=False) as c:
                r = await c.get(
                    f"{url}/api/v1/calendars/events",
                    headers={"Authorization": f"Bearer {key}"},
                    params={"start": start_iso, "end": end_iso},
                )
        except Exception as e:
            return f"캘린더 서버 연결 실패: {e}"
        if r.status_code == 401:
            return "API 키 인증에 실패했습니다. 밸브의 키를 확인해 주세요."
        if r.status_code == 403:
            return "캘린더 접근 권한이 없습니다."
        if r.status_code >= 400:
            return f"일정 조회 실패 (HTTP {r.status_code})."
        try:
            events = r.json()
        except Exception:
            return "일정 응답을 해석하지 못했습니다."

        def _fmt2(ns, all_day):
            if not ns:
                return "(시간 미정)"
            try:
                ns = int(ns)
            except (TypeError, ValueError):
                return "(시간 미정)"
            if ns > 1_000_000_000_000_000_000:
                sec = ns / 1_000_000_000
            elif ns > 1_000_000_000_000_000:
                sec = ns / 1_000_000
            elif ns > 1_000_000_000_000:
                sec = ns / 1_000
            else:
                sec = ns
            return _dt.datetime.fromtimestamp(sec)

        if span == 1:
            header = f"📅 {base.isoformat()} 일정"
        else:
            last = base + _dt.timedelta(days=span - 1)
            header = f"📅 {base.isoformat()} ~ {last.isoformat()} 일정"
        if not events:
            return f"{header}\\n예정된 일정이 없습니다."

        def _k(e):
            try:
                return int(e.get("start_at") or 0)
            except (TypeError, ValueError):
                return 0

        events = sorted(events, key=_k)
        lines = [header]
        cur_day = None
        for e in events:
            dt = _fmt2(e.get("start_at"), e.get("all_day", False))
            title = e.get("title") or "(제목 없음)"
            loc = e.get("location")
            if isinstance(dt, _dt.datetime):
                day_str = dt.strftime("%m-%d (%a)")
                time_str = "(종일)" if e.get("all_day") else dt.strftime("%H:%M")
            else:
                day_str, time_str = "?", "(시간 미정)"
            if span > 1 and day_str != cur_day:
                lines.append(f"\\n〔{day_str}〕")
                cur_day = day_str
            line = f"\\u2022 {time_str}  {title}"
            if loc:
                line += f"  @ {loc}"
            lines.append(line)
        return "\\n".join(lines)

    async def get_today_schedule(self, __user__: dict = {}) -> str:
        \"\"\"오늘의 일정을 OpenWebUI 캘린더에서 조회합니다. '오늘 일정', '오늘 스케줄', '오늘 약속' 질문에 사용.\"\"\"
        import datetime as _dt
        import httpx as _httpx
        if self.valves.CALENDAR_ADMIN_ONLY:
            role = ""
            if isinstance(__user__, dict):
                role = (__user__.get("role") or "")
            if role != "admin":
                return "이 기능은 관리자만 사용할 수 있습니다."
        key = (self.valves.OPENWEBUI_API_KEY or "").strip()
        if not key:
            return "캘린더 도구 설정(밸브)에 OpenWebUI API 키를 먼저 입력해 주세요."
        url = (self.valves.OPENWEBUI_URL or "http://open-webui:8080").rstrip("/")
        today = _dt.date.today()
        start_iso = f"{today.isoformat()}T00:00:00"
        end_iso = f"{(today + _dt.timedelta(days=1)).isoformat()}T00:00:00"
        try:
            async with _httpx.AsyncClient(timeout=15, follow_redirects=False) as c:
                r = await c.get(
                    f"{url}/api/v1/calendars/events",
                    headers={"Authorization": f"Bearer {key}"},
                    params={"start": start_iso, "end": end_iso},
                )
        except Exception as e:
            return f"캘린더 서버 연결 실패: {e}"
        if r.status_code == 401:
            return "API 키 인증에 실패했습니다. 밸브의 키를 확인해 주세요."
        if r.status_code == 403:
            return "캘린더 접근 권한이 없습니다."
        if r.status_code >= 400:
            return f"일정 조회 실패 (HTTP {r.status_code})."
        try:
            events = r.json()
        except Exception:
            return "일정 응답을 해석하지 못했습니다."

        def _fmt(ns, all_day):
            if not ns:
                return "(시간 미정)"
            try:
                ns = int(ns)
            except (TypeError, ValueError):
                return "(시간 미정)"
            if ns > 1_000_000_000_000_000_000:
                sec = ns / 1_000_000_000
            elif ns > 1_000_000_000_000_000:
                sec = ns / 1_000_000
            elif ns > 1_000_000_000_000:
                sec = ns / 1_000
            else:
                sec = ns
            d = _dt.datetime.fromtimestamp(sec)
            if all_day:
                return d.strftime("%Y-%m-%d (종일)")
            return d.strftime("%H:%M")

        header = f"📅 {today.isoformat()} 오늘의 일정"
        if not events:
            return f"{header}\\n예정된 일정이 없습니다."

        def _k(e):
            try:
                return int(e.get("start_at") or 0)
            except (TypeError, ValueError):
                return 0

        events = sorted(events, key=_k)
        lines = [header]
        for e in events:
            when = _fmt(e.get("start_at"), e.get("all_day", False))
            title = e.get("title") or "(제목 없음)"
            loc = e.get("location")
            line = f"\\u2022 {when}  {title}"
            if loc:
                line += f"  @ {loc}"
            lines.append(line)
        return "\\n".join(lines)

    async def create_event(self, title: str, start: str, duration_min: int = 60,
                           location: str = "", description: str = "",
                           reminder_min: int = None,
                           __user__: dict = {}) -> str:
        \"\"\"OpenWebUI 캘린더에 새 일정을 등록합니다. '일정 잡아줘', '미팅 등록', '약속 추가'에 사용.
        :param title: 일정 제목 (예: 시장조사 회의)
        :param start: 시작 일시 ISO 8601 (예: 2026-07-20T15:00:00). 날짜만 주면 종일 일정.
        :param duration_min: 소요 시간(분). 기본 60분. 종일 일정이면 무시.
        :param location: 장소 (선택)
        :param description: 상세 설명 (선택)
        :param reminder_min: 알림(분 전). 예 10=10분 전, 60=1시간 전, 1440=하루 전. 미지정 시 기본 10분.
        \"\"\"
        import datetime as _dt
        import httpx as _httpx
        if self.valves.CALENDAR_ADMIN_ONLY:
            role = ""
            if isinstance(__user__, dict):
                role = (__user__.get("role") or "")
            if role != "admin":
                return "이 기능은 관리자만 사용할 수 있습니다."
        if not (title or "").strip():
            return "일정 제목을 입력해 주세요."
        if not (start or "").strip():
            return "시작 일시를 입력해 주세요. 예: 2026-07-20T15:00:00"
        key = (self.valves.OPENWEBUI_API_KEY or "").strip()
        if not key:
            return "캘린더 도구 설정(밸브)에 OpenWebUI API 키를 먼저 입력해 주세요."
        url = (self.valves.OPENWEBUI_URL or "http://open-webui:8080").rstrip("/")
        # ISO 파싱: 날짜만 있으면 종일, 시각 포함이면 시간 일정
        s = start.strip().replace("Z", "").replace(" ", "T", 1)
        all_day = ("T" not in s)
        try:
            if all_day:
                dt0 = _dt.datetime.fromisoformat(s + "T00:00:00")
            else:
                dt0 = _dt.datetime.fromisoformat(s)
        except ValueError:
            return f"시작 일시 형식을 이해하지 못했습니다: {start} (예: 2026-07-20T15:00:00)"
        try:
            dur = int(duration_min)
        except (TypeError, ValueError):
            dur = 60
        dur = max(0, min(dur, 24 * 60))
        dt1 = dt0 + _dt.timedelta(minutes=(0 if all_day else dur))
        # OpenWebUI 는 나노초 epoch 를 사용 (조회 로직과 동일 단위)
        start_ns = int(dt0.timestamp() * 1_000_000_000)
        end_ns = int(dt1.timestamp() * 1_000_000_000)
        auth = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        try:
            async with _httpx.AsyncClient(timeout=15, follow_redirects=False) as c:
                # 1) 기본 캘린더 ID 조회 (이벤트 생성에 calendar_id 필수)
                lr = await c.get(f"{url}/api/v1/calendars/", headers=auth)
                if lr.status_code == 401:
                    return "API 키 인증에 실패했습니다. 밸브의 키를 확인해 주세요."
                if lr.status_code >= 400:
                    return f"캘린더 목록 조회 실패 (HTTP {lr.status_code})."
                cals = lr.json() if lr.content else []
                cal_id = None
                for cal in cals:
                    if cal.get("id") == "__scheduled_tasks__":
                        continue
                    if cal.get("is_default"):
                        cal_id = cal.get("id"); break
                if not cal_id:
                    for cal in cals:
                        if cal.get("id") != "__scheduled_tasks__":
                            cal_id = cal.get("id"); break
                if not cal_id:
                    return "등록할 캘린더를 찾지 못했습니다. OpenWebUI에서 캘린더를 먼저 만들어 주세요."
                # 2) 이벤트 생성
                payload = {"calendar_id": cal_id, "title": title.strip(),
                           "start_at": start_ns, "end_at": end_ns, "all_day": all_day}
                if location.strip(): payload["location"] = location.strip()
                if description.strip(): payload["description"] = description.strip()
                if reminder_min is not None:
                    try:
                        payload["meta"] = {"alert_minutes": int(reminder_min)}
                    except (TypeError, ValueError):
                        pass
                r = await c.post(f"{url}/api/v1/calendars/events/create",
                                 headers=auth, json=payload)
        except Exception as e:
            return f"캘린더 서버 연결 실패: {e}"
        if r.status_code == 401:
            return "API 키 인증에 실패했습니다. 밸브의 키를 확인해 주세요."
        if r.status_code == 403:
            return "캘린더 등록 권한이 없습니다. (관리자 또는 캘린더 권한 필요)"
        if r.status_code >= 400:
            return f"일정 등록 실패 (HTTP {r.status_code}): {r.text[:120]}"
        when_txt = dt0.strftime("%Y-%m-%d") if all_day else dt0.strftime("%Y-%m-%d %H:%M")
        msg = f"✅ 일정 등록 완료\\n📌 {title.strip()}\\n🕒 {when_txt}"
        if not all_day:
            msg += f" (~{dt1.strftime('%H:%M')})"
        if location.strip():
            msg += f"\\n📍 {location.strip()}"
        if reminder_min is not None:
            try:
                _rm = int(reminder_min)
                if _rm >= 1440 and _rm % 1440 == 0:
                    msg += f"\\n🔔 {_rm // 1440}일 전 알림"
                elif _rm >= 60 and _rm % 60 == 0:
                    msg += f"\\n🔔 {_rm // 60}시간 전 알림"
                else:
                    msg += f"\\n🔔 {_rm}분 전 알림"
            except (TypeError, ValueError):
                pass
        if description.strip():
            msg += f"\\n📝 {description.strip()}"
        # 🔔 알림 시각에 관리자에게 전화+SMS: twilio-bot 예약 API 호출 (밸브로 on/off)
        if reminder_min is not None and getattr(self.valves, "ENABLE_CALL_SMS_REMINDER", True) \\
           and getattr(self.valves, "TWILIO_BOT_SECRET", ""):
            try:
                _rm2 = int(reminder_min)
            except (TypeError, ValueError):
                _rm2 = 0
            if _rm2 > 0:
                try:
                    _bot = self.valves.TWILIO_BOT_URL.rstrip("/")
                    async with httpx.AsyncClient(timeout=10) as _c:
                        _rr = await _c.post(
                            _bot + "/calendar-reminder",
                            headers={"X-API-Secret": self.valves.TWILIO_BOT_SECRET,
                                     "Content-Type": "application/json"},
                            json={"title": title.strip(),
                                  "start_epoch": int(dt0.timestamp()),
                                  "reminder_min": _rm2},
                        )
                    if _rr.status_code == 200 and _rr.json().get("status") == "scheduled":
                        msg += "\\n📞 알림 시각에 전화·문자 발송 예약됨"
                except Exception:
                    pass  # 알림 예약 실패해도 일정 등록은 성공
        return msg

    def _headers(self) -> dict:'''

method_anchor = "    def _headers(self) -> dict:"
if "async def get_today_schedule" in code and "async def create_event" in code and "async def get_schedule" in code:
    ok_list.append("캘린더 메서드 이미 존재")
elif method_anchor in code:
    code = code.replace(method_anchor, CAL_METHOD, 1)
    ok_list.append("get_today_schedule + get_schedule + create_event 메서드 추가")
else:
    print("  ⚠️  _headers 앵커 불일치 — 캘린더 메서드 삽입 실패")

with open(tool_path, 'w', encoding='utf-8') as f:
    f.write(code)
print(f"  📋 적용: {len(ok_list)}개")
for p in ok_list:
    print(f"    ✅ {p}")
print(f"  📋 최종 라인: {len(code.splitlines())}")
CAL_UPGRADE

ok "openwebui_tool.py 캘린더 Tool 추가 완료"
info "신규 Tool: get_today_schedule / get_schedule / create_event (밸브에 OpenWebUI API 키 입력 필요)"

############################################
# 5-3. openwebui_tool.py 사용자별 메모리 연동 (이메일 → X-User-Id 헤더)
# - __user__ 에서 이메일 추출해 self._uid 저장
# - _headers() 가 X-User-Id 헤더 자동 첨부
# - 메모리 관련 Tool 들이 __user__ 를 받도록 시그니처 확장
############################################
step "5-3/9  openwebui_tool.py 사용자별 메모리 연동"

python3 - "${AGENT_DIR}" << 'TOOL_PERUSER'
import sys
tool_path = sys.argv[1] + '/openwebui_tool.py'
try:
    with open(tool_path, encoding='utf-8') as f: code = f.read()
except FileNotFoundError:
    print(f"  ❌ 파일 없음: {tool_path}"); sys.exit(1)

ok_list = []

# 1) __init__ 에 self._uid 추가
OLD_INIT = '''        self.valves = self.Valves()
        self._session_id: Optional[str] = None
        self._cache: Dict[str, dict] = {}'''
NEW_INIT = '''        self.valves = self.Valves()
        self._session_id: Optional[str] = None
        self._cache: Dict[str, dict] = {}
        self._uid: str = ""  # [PER-USER] 현재 사용자 이메일(요청별로 갱신)'''
if OLD_INIT in code:
    code = code.replace(OLD_INIT, NEW_INIT); ok_list.append("__init__ self._uid")

# 2) _headers() 가 X-User-Id 헤더 첨부 + __user__ 파서 추가
OLD_HDR = '''    def _headers(self) -> dict:
        headers = {"Content-Type": "application/json"}
        if self.valves.BROWSER_AGENT_API_KEY:
            headers["Authorization"] = f"Bearer {self.valves.BROWSER_AGENT_API_KEY}"
        return headers'''
NEW_HDR = '''    def _set_user(self, __user__):
        """[PER-USER] OpenWebUI 가 넘긴 __user__ 에서 이메일을 추출해 저장.
        식별 성공 시 True, 실패(이메일/id 없음) 시 False 반환."""
        self._uid = ""
        try:
            if isinstance(__user__, dict):
                self._uid = (__user__.get("email") or __user__.get("id") or "").strip()
        except Exception:
            self._uid = ""
        return bool(self._uid)

    def _headers(self) -> dict:
        headers = {"Content-Type": "application/json"}
        if self.valves.BROWSER_AGENT_API_KEY:
            headers["Authorization"] = f"Bearer {self.valves.BROWSER_AGENT_API_KEY}"
        if self._uid:
            headers["X-User-Id"] = self._uid  # [PER-USER] 사용자별 메모리 라우팅
        return headers'''
if OLD_HDR in code:
    code = code.replace(OLD_HDR, NEW_HDR); ok_list.append("_headers X-User-Id + _set_user")

# 3) 메모리에 영향을 주는 Tool 들이 __user__ 를 받고 _set_user 호출
#    browse, get_memory, update_memory, clear_memory
OLD_BROWSE = '''    async def browse(self, task: str, __event_emitter__=None):
        """Open a URL and perform a task. Do NOT use for weather/prices/stocks - use dedicated functions.
        :param task: URL + instruction
        """'''
NEW_BROWSE = '''    async def browse(self, task: str, __event_emitter__=None, __user__={}):
        """Open a URL and perform a task. Do NOT use for weather/prices/stocks - use dedicated functions.
        :param task: URL + instruction
        """
        self._set_user(__user__)'''
if OLD_BROWSE in code:
    code = code.replace(OLD_BROWSE, NEW_BROWSE); ok_list.append("browse __user__")

OLD_GM = '''    async def get_memory(self, __event_emitter__=None):
        """저장된 사용자 정보 조회."""
        if not self.valves.ENABLE_MEMORY: return "메모리 비활성화"'''
NEW_GM = '''    async def get_memory(self, __event_emitter__=None, __user__={}):
        """저장된 사용자 정보 조회."""
        if not self._set_user(__user__):
            return "사용자 식별 실패 — 로그인 정보(이메일)가 없어 개인 메모리를 조회할 수 없습니다."
        if not self.valves.ENABLE_MEMORY: return "메모리 비활성화"'''
if OLD_GM in code:
    code = code.replace(OLD_GM, NEW_GM); ok_list.append("get_memory __user__")

OLD_UM = '''    async def update_memory(self, info: str, __event_emitter__=None):
        """사용자 정보 저장.
        :param info: 기억할 정보
        """
        if not self.valves.ENABLE_MEMORY: return "메모리 비활성화"'''
NEW_UM = '''    async def update_memory(self, info: str, __event_emitter__=None, __user__={}):
        """사용자 정보 저장.
        :param info: 기억할 정보
        """
        if not self._set_user(__user__):
            return "사용자 식별 실패 — 로그인 정보(이메일)가 없어 메모리를 저장하지 않았습니다."
        if not self.valves.ENABLE_MEMORY: return "메모리 비활성화"'''
if OLD_UM in code:
    code = code.replace(OLD_UM, NEW_UM); ok_list.append("update_memory __user__")

OLD_CM = '''    async def clear_memory(self, __event_emitter__=None):
        """저장된 모든 메모리 삭제."""'''
NEW_CM = '''    async def clear_memory(self, __event_emitter__=None, __user__={}):
        """저장된 모든 메모리 삭제."""
        if not self._set_user(__user__):
            return "사용자 식별 실패 — 로그인 정보(이메일)가 없어 삭제를 수행하지 않았습니다."'''
if OLD_CM in code:
    code = code.replace(OLD_CM, NEW_CM); ok_list.append("clear_memory __user__")

# multi_agent_browse 는 이미 __user__ 를 받으므로 _set_user 만 연결
OLD_MAB = '''    async def multi_agent_browse(self, task: str, __event_emitter__=None, __user__={}):'''
if OLD_MAB in code and 'self._set_user(__user__)' in code:
    # multi_agent_browse 본문 첫 줄에 _set_user 삽입 (docstring 다음)
    import re as _re
    m = _re.search(r'(async def multi_agent_browse\(self, task, __event_emitter__=None, __user__=\{\}\):\n\s*"""[^"]*?""")', code, _re.DOTALL)
    if m and 'self._set_user(__user__)' not in code[m.end():m.end()+60]:
        code = code[:m.end()] + '\n        self._set_user(__user__)' + code[m.end():]
        ok_list.append("multi_agent_browse _set_user 연결")

with open(tool_path, 'w', encoding='utf-8') as f: f.write(code)
print(f"  📋 적용: {len(ok_list)}개")
for p in ok_list: print(f"    ✅ {p}")
print(f"  📋 최종 라인: {len(code.splitlines())}")
TOOL_PERUSER

ok "openwebui_tool.py 사용자별 메모리 연동 완료"


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
# 🔒 메인 스크립트와 동일한 공유 권한(setgid+그룹쓰기) 적용 — uid 1001/1002 공유 충돌 방지
chmod 2775 "${HOME}/ai-share" 2>/dev/null || chmod 775 "${HOME}/ai-share" 2>/dev/null || true
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

# networks: 섹션 정합성 보장
# ① 아예 없으면 추가
# ② 있지만 비어있으면 openwebui_net 추가
# ③ 있고 내용도 있지만 openwebui_net 정의 없으면 추가
python3 - "$COMPOSE_FILE" << 'PYNETFIX'
import re, sys
p = sys.argv[1]
with open(p) as f: c = f.read()

# ⚠️  \s*$ 는 다음 줄에 내용이 있어도 매칭됨 → [ \t]*$ 로 현재 줄만 검사
has_networks     = bool(re.search(r'^networks:', c, re.MULTILINE))
has_openwebui    = bool(re.search(r'^\s+openwebui_net\s*:', c, re.MULTILINE))
networks_empty   = bool(re.search(r'^networks:[ \t]*$', c, re.MULTILINE))  # 같은 줄에 내용 없음

changed = False

if not has_networks:
    # networks: 섹션 자체 없음 → 통째로 추가
    if not c.endswith('\n'): c += '\n'
    c += 'networks:\n  openwebui_net:\n    driver: bridge\n'
    changed = True
elif not has_openwebui:
    if networks_empty:
        # networks: 만 있고 내용 없음 → 바로 아래에 추가
        c = re.sub(
            r'^(networks:[ \t]*)$',
            r'\1\n  openwebui_net:\n    driver: bridge',
            c, flags=re.MULTILINE, count=1
        )
    else:
        # networks: 에 다른 내용은 있지만 openwebui_net 없음 → 첫 줄 뒤에 추가
        c = re.sub(
            r'^(networks:[ \t]*)(\n)',
            r'\1\2  openwebui_net:\n    driver: bridge\n',
            c, flags=re.MULTILINE, count=1
        )
    changed = True

if changed:
    with open(p, 'w') as f: f.write(c)
    print('  networks 섹션 정리 완료')
else:
    print('  networks 섹션 이상 없음 (openwebui_net 이미 존재)')
PYNETFIX

export COMPOSE_FILE SHM_SIZE BUILD_START_PERIOD CONTAINER_CPUS CONTAINER_MEMORY \
       BROWSER_API_KEY OWUI_API_KEY \
       INTERNAL_TOKEN OPENWEBUI_INTERNAL_URL LITE_MODE SCREEN_RESOLUTION \
       MAX_STEPS_AGENT HAS_GPU OWUI_HOST AGENT_DIR IS_WSL HOME

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
groq_model   = os.environ.get("GROQ_MODEL",           "qwen/qwen3.8-27b")
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
home         = os.environ.get("HOME",                  "")
# [FIX] docker-compose는 '~'를 확장하지 않으므로 절대경로 사용
ai_share_dir = f"{home}/ai-share" if home else "./ai-share"

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
      - TASK_TIMEOUT=120
      - NAVER_CLIENT_ID=${{NAVER_CLIENT_ID:-}}
      - NAVER_CLIENT_SECRET=${{NAVER_CLIENT_SECRET:-}}
      - SEARCH_TIMEOUT=${{SEARCH_TIMEOUT:-15}}
      - SEARCH_CACHE_TTL=${{SEARCH_CACHE_TTL:-300}}
      - MULTI_TIMEOUT=300
      - MULTI_BUDGET_USD=${{MULTI_BUDGET_USD:-0}}
      - MAX_CONCURRENT=3
      - SMS_NOTIFY_TO=${{SMS_NOTIFY_TO:-}}
      - SMS_NOTIFY_URL=${{SMS_NOTIFY_URL:-http://openapi-tools:8000/tools/send-sms}}
      - SMS_MAX_RECIPIENTS=${{SMS_MAX_RECIPIENTS:-5}}
      - SMS_ALLOWLIST=${{SMS_ALLOWLIST:-}}
      - SMS_HOURLY_CAP=${{SMS_HOURLY_CAP:-50}}
      - ENABLE_REQUEST_SIGNING=false
      - BROWSER_PROXY=
      - BROWSER_POOL_SIZE=0
      - GROQ_API_KEY=${{GROQ_API_KEY:-}}
      - PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
      - REQUIRE_USER_ID=${{REQUIRE_USER_ID:-true}}
    volumes:
      - ./browser-agent/data:/app/data
      - ./browser-agent/secrets:/app/secrets:ro
      - {ai_share_dir}:/app/data/user_files
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
          pids: 100
        reservations:
          memory: 512M
{gpu_runtime}{security_block}
    ulimits:
      nofile:
        soft: 1024
        hard: 2048
      nproc:
        soft: 128
        hard: 256
    tmpfs:
      - /tmp:size=200M,mode=1777
      - /app/logs:size=32M,uid=1001,gid=1001,mode=0755
      - /home/appuser:size=320M,uid=1001,gid=1001,mode=0755
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

# ── networks: 섹션 최종 보정 ─────────────────────────────────────
with open(p) as f: c2 = f.read()
has_ow = bool(re.search(r'^\s+openwebui_net\s*:', c2, re.MULTILINE))
net_empty = bool(re.search(r'^networks:[ \t]*$', c2, re.MULTILINE))
if not has_ow:
    if net_empty:
        c2 = re.sub(r'^(networks:[ \t]*)$',
                    r'\1\n  openwebui_net:\n    driver: bridge',
                    c2, flags=re.MULTILINE, count=1)
    else:
        if not re.search(r'^networks:', c2, re.MULTILINE):
            c2 += '\nnetworks:\n  openwebui_net:\n    driver: bridge\n'
        else:
            c2 = re.sub(r'^(networks:[ \t]*)(\n)',
                        r'\1\2  openwebui_net:\n    driver: bridge\n',
                        c2, flags=re.MULTILINE, count=1)
    with open(p, 'w') as f: f.write(c2)
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

# ── [문제3 해결] compose 네트워크 재구성으로 기존 서비스가 내려갔는지 점검·복구 ──
# browser-agent 추가 시 최상위 networks: 섹션이 새로 생기면서, 드물게
# 기존 컨테이너(open-webui/twilio-bot/openapi-tools/qdrant)가 재생성/중지될 수 있음.
# up -d browser-agent 는 의존 서비스를 자동 기동하지 않으므로 여기서 명시적으로 보정.
info "기존 OpenWebUI 서비스 상태 점검 중 (네트워크 재구성 영향 확인)..."
_EXPECTED_SVCS="qdrant openapi-tools open-webui twilio-bot realtime-voice"
_DOWN_SVCS=""
for _svc in $_EXPECTED_SVCS; do
    # 서비스가 compose 정의에 존재할 때만 검사
    if docker compose config --services 2>/dev/null | grep -qx "$_svc"; then
        if ! docker compose ps "$_svc" 2>/dev/null | grep -qE "running|Up"; then
            _DOWN_SVCS="$_DOWN_SVCS $_svc"
        fi
    fi
done
if [ -n "$_DOWN_SVCS" ]; then
    warn "네트워크 재구성으로 중지된 서비스 감지:${_DOWN_SVCS} → 자동 복구 시도"
    # browser-agent 를 제외한 나머지 서비스만 재기동 (browser-agent 는 위에서 이미 처리)
    docker compose up -d${_DOWN_SVCS} 2>&1 || \
        docker compose up -d 2>&1 || \
        warn "자동 복구 실패 — 수동 실행 필요: cd ~/OpenWebUI && docker compose up -d"
    sleep 3
    # 복구 결과 재확인
    _STILL_DOWN=""
    for _svc in $_DOWN_SVCS; do
        if ! docker compose ps "$_svc" 2>/dev/null | grep -qE "running|Up"; then
            _STILL_DOWN="$_STILL_DOWN $_svc"
        fi
    done
    if [ -n "$_STILL_DOWN" ]; then
        warn "다음 서비스가 여전히 중지 상태입니다:${_STILL_DOWN}"
        warn "수동 복구: cd ~/OpenWebUI && docker compose up -d"
    else
        ok "중지됐던 서비스 정상 복구 완료"
    fi
else
    ok "기존 서비스 모두 정상 동작 중 (네트워크 재구성 영향 없음)"
fi

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
# [KEY-SYNC] 서버 API 키를 도구 Valves 동기화용으로 전달
export BROWSER_API_KEY
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

# [KEY-SYNC] 서버(browser-agent)가 인정하는 API 키를 도구 Valves에 함께 등록한다.
#   이 값을 넣지 않으면, 기존 도구를 update할 때 Valves에 예전 키가 남아
#   서버 키와 어긋나 /search 가 401 Unauthorized 로 실패한다.
_browser_key = os.environ.get("BROWSER_API_KEY", "")

tool_payload = {
    "id": TOOL_ID,
    "name": "AI 브라우저 에이전트",
    "content": tool_content,
    "meta": {
        "description": "AI 브라우저 에이전트: browse_web으로 웹 작업, search_web으로 검색, search_wikipedia로 백과사전 검색, check_weather로 날씨 확인. Browser Use + Groq 기반."
    }
}
# Valves 초기값(있을 때만) — 서버 키와 자동 동기화
if _browser_key:
    tool_payload["valves"] = {"BROWSER_AGENT_API_KEY": _browser_key}

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

# [KEY-SYNC] 도구 등록/업데이트와 별개로, Valves 키를 서버 키로 확실히 재설정한다.
#   create 시 valves 필드가 무시되는 OpenWebUI 버전 대비 + 기존 도구의
#   낡은 Valves 키 덮어쓰기. 이 단계 덕분에 재실행 후에도 챗 검색이 401 없이 동작한다.
if _browser_key:
    _valves_body = {"BROWSER_AGENT_API_KEY": _browser_key}
    _synced = False
    for _vurl in (f"{base}/api/v1/tools/id/{TOOL_ID}/valves/update",
                  f"{base}/api/v1/tools/id/{TOOL_ID}/valves"):
        vs, vb = req(_vurl, t=token, p=_valves_body)
        if vs in (200, 201):
            print("  🔑 도구 Valves API 키 동기화 완료")
            _synced = True
            break
    if not _synced:
        print("  ⚠️  Valves 자동 동기화 실패 — 관리자 패널 → 도구 → Valves 에서")
        print("      BROWSER_AGENT_API_KEY 를 secrets/api_key 값으로 직접 넣어 주세요.")
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

# ── 8-5b. [KEY-SYNC] API 키 인증 자가진단 ─────────────────────────────
#   서버 키로 /search 를 실제 호출해 인증(401)이 통과하는지 확인한다.
#   401 이면 도구 Valves 키와 서버 키가 어긋난 것 → 챗 검색이 실패한다.
info "8-5b. API 키 인증(컨테이너↔서버) 자가진단..."
AUTH_CODE=$(docker compose exec -T browser-agent sh -c \
    'curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 \
      -X POST http://localhost:8001/search \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $(cat /app/secrets/api_key 2>/dev/null || echo x)" \
      -d "{\"query\":\"핑\",\"display\":1}"' 2>/dev/null || echo "000")
if [ "$AUTH_CODE" = "401" ]; then
    warn "API 키 인증 실패(401) — 도구 Valves 키가 서버 키와 다릅니다."
    info "  해결: 관리자 패널 → 도구 → 'AI 브라우저 에이전트' → Valves →"
    info "        BROWSER_AGENT_API_KEY 에 아래 값을 넣고 저장:"
    info "        $(cat "${SECRETS_DIR}/api_key" 2>/dev/null || sudo cat "${SECRETS_DIR}/api_key" 2>/dev/null || echo '(secrets/api_key 확인)')"
    VERIFY_OK=false
else
    ok "API 키 인증 통과 (HTTP ${AUTH_CODE}) — 챗 검색 정상 동작 예상"
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
        warn "secrets 권한: ${SEC_PERM} — 750으로 수정"
        # [FIX-28] 컨테이너 사용자(uid 1001) 소유이므로 sudo 필요
        sudo chmod 750 "$SECRETS_DIR" 2>/dev/null || {
            info "sudo 권한 없음 — 수동 실행 필요: sudo chmod 750 $SECRETS_DIR"
        }
    fi
fi

# ── 8-11. 디렉토리 구조 최종 확인 ────────────────────────────────────
info "8-11. 디렉토리 구조 확인..."
for CHECK_DIR in \
    "${OWUI_DIR}" \
    "${AGENT_DIR}" \
    "${TOOLS_API_DIR}" \
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

# ── [문제1 해결] 기존 telegram 브릿지를 openwebui_net 에 자동 재연결 ───────────
# 설치 순서가 telegram(Phase 2) → browser-agent(Phase 3)인 경우,
# telegram 설치 시점엔 openwebui_net 이 없어 browser-agent 연동이 누락된다.
# 이제 openwebui_net 이 생성되었으므로, 이미 떠 있는 telegram 컨테이너를
# 해당 네트워크에 즉시 연결하고 BROWSER_AGENT_URL 을 컨테이너명 주소로 갱신한다.
info "8-12. 기존 Telegram 브릿지 ↔ browser-agent 자동 연결 확인..."
_TG_CONTAINER="telegram-openwebui-bridge"
if docker network ls --format '{{.Name}}' 2>/dev/null | grep -qx "openwebui_net"; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$_TG_CONTAINER"; then
        # 이미 openwebui_net 에 연결돼 있는지 확인
        _ALREADY=$(docker inspect "$_TG_CONTAINER" \
            --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null | tr ' ' '\n' | grep -cx "openwebui_net" || echo 0)
        if [ "$_ALREADY" = "0" ]; then
            if docker network connect openwebui_net "$_TG_CONTAINER" 2>/dev/null; then
                ok "Telegram 브릿지를 openwebui_net 에 연결했습니다."
            else
                warn "Telegram 브릿지 자동 연결 실패 — telegram 스크립트를 재실행하세요."
            fi
        else
            ok "Telegram 브릿지가 이미 openwebui_net 에 연결돼 있습니다."
        fi

        # BROWSER_AGENT_URL 을 컨테이너명 기반으로 갱신 (.env)
        _TG_ENV="${TELEGRAM_DIR}/.env"
        if [ -f "$_TG_ENV" ]; then
            if grep -q "^BROWSER_AGENT_URL=" "$_TG_ENV" 2>/dev/null; then
                sed -i 's#^BROWSER_AGENT_URL=.*#BROWSER_AGENT_URL=http://browser-agent:8001#' "$_TG_ENV" 2>/dev/null || true
            else
                echo "BROWSER_AGENT_URL=http://browser-agent:8001" >> "$_TG_ENV"
            fi
            # browser-agent API 키도 telegram secrets 로 동기화 (있을 때만)
            if [ -f "${SECRETS_DIR}/api_key" ] && [ -d "${TELEGRAM_DIR}/secrets" ]; then
                cp -f "${SECRETS_DIR}/api_key" "${TELEGRAM_DIR}/secrets/browser_agent_api_key" 2>/dev/null || true
                chmod 600 "${TELEGRAM_DIR}/secrets/browser_agent_api_key" 2>/dev/null || true
            fi
            # 변경사항 반영을 위해 telegram 컨테이너 재시작
            if command -v docker >/dev/null 2>&1; then
                ( cd "$TELEGRAM_DIR" 2>/dev/null && docker compose restart 2>/dev/null ) || \
                    docker restart "$_TG_CONTAINER" 2>/dev/null || true
                ok "Telegram 브릿지 재시작 완료 — browser-agent 연동 활성화됨"
            fi
        fi
    else
        info "Telegram 브릿지 미실행 — browser-agent 설치만 완료 (정상)."
        info "ℹ️  나중에 telegram 스크립트를 실행하면 openwebui_net 에 자동 연결됩니다."
    fi
fi

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
info "  Telegram:     ${TELEGRAM_DIR}/.env 에 BOT TOKEN 입력 후 실행"
info "─────────────────────────────────────────────────────────────"
info "  Twilio 전화봇: 별도 스크립트 start-twilio-bot.sh 로 ~/TwilioBot 에 설치"
info "  Phase 3 시작: cd ~/telegram-openwebui-bridge && docker compose up -d"
info "  전체 로그:    docker compose logs -f browser-agent"
info "  Multi-Agent: POST http://localhost:8001/browse/multi (Browser Use+Groq)"
info "  ※ Multi-Agent는 비교/추천/분석/계획 등 복잡한 작업에 사용"
info "  보안 감사:    cat ${AGENT_DIR}/data/audit/agent.log"
