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
# [v7] 검색 API 키 입력 (네이버 검색 API + Tavily)
# ══════════════════════════════════════════════════════════════════════
step "검색 API 키 설정 (네이버 + Tavily)"
info "정보 조회는 브라우저 긁기 대신 공식 검색 API를 사용합니다."
info "  • 네이버 검색 API: 한국어 검색 (https://developers.naver.com, 무료/일 25,000건)"
info "  • Tavily API: 해외/영어 검색 (https://app.tavily.com, 무료/월 1,000건)"
info "  둘 다 선택사항입니다. 입력을 건너뛰면 해당 검색 소스만 비활성화됩니다."

EXISTING_NAVER_ID="$(_env NAVER_CLIENT_ID)"
if [ -n "$EXISTING_NAVER_ID" ]; then
    ok "기존 NAVER_CLIENT_ID 감지 ($(masked "$EXISTING_NAVER_ID")) — 재사용"
    NAVER_CLIENT_ID="$EXISTING_NAVER_ID"
    NAVER_CLIENT_SECRET="$(_env NAVER_CLIENT_SECRET)"
else
    echo -e "${Y}네이버 Client ID (Enter=건너뜀):${N}"
    NAVER_CLIENT_ID=$(read_secret "  🟢 NAVER Client ID: " 120 skip)
    if [ -n "$NAVER_CLIENT_ID" ]; then
        echo -e "${Y}네이버 Client Secret:${N}"
        NAVER_CLIENT_SECRET=$(read_secret "  🟢 NAVER Client Secret: " 120 skip)
    fi
fi

EXISTING_TAVILY="$(_env TAVILY_API_KEY)"
if [ -n "$EXISTING_TAVILY" ]; then
    ok "기존 TAVILY_API_KEY 감지 ($(masked "$EXISTING_TAVILY")) — 재사용"
    TAVILY_API_KEY="$EXISTING_TAVILY"
else
    echo -e "${Y}Tavily API Key (tvly-로 시작, Enter=건너뜀):${N}"
    TAVILY_API_KEY=$(read_secret "  🔵 TAVILY API Key: " 120 skip)
    if [ -n "$TAVILY_API_KEY" ] && [[ "$TAVILY_API_KEY" != tvly-* ]]; then
        warn "Tavily 키는 보통 'tvly-'로 시작합니다. 입력값을 확인하세요."
    fi
fi

# .env 저장 (기존 값 치환 또는 추가)
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
_set_env TAVILY_API_KEY "$TAVILY_API_KEY"
chmod 600 "$ENV_FILE" 2>/dev/null || true

if [ -n "$NAVER_CLIENT_ID" ]; then ok "네이버 검색 API 키 저장됨"; else info "네이버 키 미설정 — 한국어 검색은 Tavily로 폴백"; fi
if [ -n "$TAVILY_API_KEY" ]; then ok "Tavily API 키 저장됨"; else info "Tavily 키 미설정 — 해외 검색은 네이버로 폴백"; fi
if [ -z "$NAVER_CLIENT_ID" ] && [ -z "$TAVILY_API_KEY" ]; then
    warn "검색 API 키가 하나도 없습니다. /search 는 비활성 상태가 되며,"
    warn "기존 브라우징(open_and_summarize 등)만 동작합니다."
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
    "qOydvCDsiqTthZ0g7LWc64yAIDMw7LSICgojIOKUgOKUgCBbdjddIOqygOyDiSBBUEkg7YKkICjr"
    "hKTsnbTrsoQgKyBUYXZpbHkpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApOQVZFUl9DTElFTlRfSUQgICAgID0gb3MuZ2V0"
    "ZW52KCJOQVZFUl9DTElFTlRfSUQiLCAiIikKTkFWRVJfQ0xJRU5UX1NFQ1JFVCA9IG9zLmdldGVu"
    "digiTkFWRVJfQ0xJRU5UX1NFQ1JFVCIsICIiKQpUQVZJTFlfQVBJX0tFWSAgICAgID0gb3MuZ2V0"
    "ZW52KCJUQVZJTFlfQVBJX0tFWSIsICIiKQpTRUFSQ0hfVElNRU9VVCAgICAgID0gaW50KG9zLmdl"
    "dGVudigiU0VBUkNIX1RJTUVPVVQiLCAiMTUiKSkKU0VBUkNIX0NBQ0hFX1RUTCAgICA9IGludChv"
    "cy5nZXRlbnYoIlNFQVJDSF9DQUNIRV9UVEwiLCAiMzAwIikpCl9zZWFyY2hfY2FjaGUgPSB7fQoK"
    "IyBbU0VDVVJJVFldIO2XiOyaqSDrj4TrqZTsnbggKOu5iOqwkiA9IOyghOyytCDtl4jsmqkpCkFM"
    "TE9XRURfT1JJR0lOUyA9IG9zLmdldGVudigiQUxMT1dFRF9PUklHSU5TIiwgIiIpLnNwbGl0KCIs"
    "IikKQUxMT1dFRF9PUklHSU5TID0gW28uc3RyaXAoKSBmb3IgbyBpbiBBTExPV0VEX09SSUdJTlMg"
    "aWYgby5zdHJpcCgpXQoKIyBbU0VDVVJJVFldIOywqOuLqCBVUkwg7Yyo7YS0CkJMT0NLRURfVVJM"
    "X1BBVFRFUk5TID0gWwogICAgciJeZmlsZTovLyIsIHIiXmphdmFzY3JpcHQ6IiwgciJeZGF0YToi"
    "LAogICAgciJeZnRwOi8vIiwgciJeY2hyb21lOi8vIiwgciJeYWJvdXQ6IiwKICAgIHIibG9jYWxo"
    "b3N0OlxkKy9hZG1pbiIsIHIiMTI3XC4wXC4wXC4xIiwKICAgIHIiMTY5XC4yNTRcLiIsIHIiMTBc"
    "LlxkK1wuXGQrXC5cZCsiLCAgIyDrgrTrtoAg64Sk7Yq47JuM7YGsCiAgICByIjE5MlwuMTY4XC4i"
    "LCByIjE3MlwuKDFbNi05XXwyXGR8M1swMV0pXC4iLApdCgojIOKUgOKUgCBSYXRlIExpbWl0ZXIg"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACmxpbWl0ZXIgPSBMaW1pdGVyKGtleV9m"
    "dW5jPWdldF9yZW1vdGVfYWRkcmVzcykKCiMg4pSA4pSAIExMTSDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKbGxtID0gTm9uZQoKZGVm"
    "IF9sb2FkX2FwaV9rZXkoKToKICAgIGlmIEFQSV9LRVk6IHJldHVybiBBUElfS0VZCiAgICB0cnk6"
    "CiAgICAgICAgcCA9IFBhdGgoIi9hcHAvc2VjcmV0cy9hcGlfa2V5IikKICAgICAgICBpZiBwLmV4"
    "aXN0cygpOiByZXR1cm4gcC5yZWFkX3RleHQoKS5zdHJpcCgpCiAgICBleGNlcHQgRXhjZXB0aW9u"
    "OiBwYXNzCiAgICByZXR1cm4gIiIKCiMgW1NFQ1VSSVRZXSDsg4HsiJgg7Iuc6rCEIOu5hOq1kOuh"
    "nCDtg4DsnbTrsI0g6rO16rKpIOuwqeyngApkZWYgdmVyaWZ5X2FwaV9rZXkocmVxdWVzdDogUmVx"
    "dWVzdCk6CiAgICBhdXRoID0gcmVxdWVzdC5oZWFkZXJzLmdldCgiQXV0aG9yaXphdGlvbiIsICIi"
    "KQogICAga2V5ID0gX2xvYWRfYXBpX2tleSgpCiAgICBpZiBub3Qga2V5OiByZXR1cm4gVHJ1ZQog"
    "ICAgdG9rZW4gPSBhdXRoLnJlcGxhY2UoIkJlYXJlciAiLCAiIikuc3RyaXAoKQogICAgaWYgbm90"
    "IHRva2VuOgogICAgICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiQVVUSF9NSVNTSU5HfHtyZXF1ZXN0"
    "LmNsaWVudC5ob3N0fXx7cmVxdWVzdC51cmwucGF0aH0iKQogICAgICAgIHJhaXNlIEhUVFBFeGNl"
    "cHRpb24oc3RhdHVzX2NvZGU9NDAxLCBkZXRhaWw9IkF1dGhvcml6YXRpb24gcmVxdWlyZWQiKQog"
    "ICAgaWYgbm90IGhtYWMuY29tcGFyZV9kaWdlc3QodG9rZW4uZW5jb2RlKCksIGtleS5lbmNvZGUo"
    "KSk6CiAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJBVVRIX0ZBSUx8e3JlcXVlc3QuY2xpZW50"
    "Lmhvc3R9fHtyZXF1ZXN0LnVybC5wYXRofSIpCiAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbihz"
    "dGF0dXNfY29kZT00MDMsIGRldGFpbD0iSW52YWxpZCBBUEkga2V5IikKICAgIHJldHVybiBUcnVl"
    "CgojIFtTRUNVUklUWV0gVVJMIOqygOymnQpkZWYgdmFsaWRhdGVfdXJsKHVybDogc3RyKSAtPiBi"
    "b29sOgogICAgaWYgbm90IHVybDogcmV0dXJuIFRydWUKICAgIHRyeToKICAgICAgICBwYXJzZWQg"
    "PSB1cmxwYXJzZSh1cmwpCiAgICAgICAgaWYgcGFyc2VkLnNjaGVtZSBub3QgaW4gKCJodHRwIiwg"
    "Imh0dHBzIiwgIiIpOgogICAgICAgICAgICByZXR1cm4gRmFsc2UKICAgICAgICBmb3IgcGF0dGVy"
    "biBpbiBCTE9DS0VEX1VSTF9QQVRURVJOUzoKICAgICAgICAgICAgaWYgX3JlLnNlYXJjaChwYXR0"
    "ZXJuLCB1cmwsIF9yZS5JR05PUkVDQVNFKToKICAgICAgICAgICAgICAgIHJldHVybiBGYWxzZQog"
    "ICAgICAgIHJldHVybiBUcnVlCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHJldHVybiBG"
    "YWxzZQoKIyBbU0VDVVJJVFldIOyeheugpSDsg4jri4jtg4DsnbTsp5UKZGVmIHNhbml0aXplX3Rh"
    "c2sodGFzazogc3RyKSAtPiBzdHI6CiAgICAjIOygnOyWtCDrrLjsnpAg7KCc6rGwCiAgICB0YXNr"
    "ID0gIiIuam9pbihjIGZvciBjIGluIHRhc2sgaWYgYy5pc3ByaW50YWJsZSgpIG9yIGMgaW4gIlxu"
    "XHQiKQogICAgIyDtlITroaztlITtirgg7J247KCd7IWYIO2MqO2EtCDqsr3qs6AKICAgIGluamVj"
    "dGlvbl9wYXR0ZXJucyA9IFsKICAgICAgICAiaWdub3JlIHByZXZpb3VzIiwgImlnbm9yZSBhYm92"
    "ZSIsICJkaXNyZWdhcmQiLAogICAgICAgICJzeXN0ZW0gcHJvbXB0IiwgInlvdSBhcmUgbm93Iiwg"
    "Im5ldyBpbnN0cnVjdGlvbnMiLAogICAgICAgICJmb3JnZXQgZXZlcnl0aGluZyIsICJvdmVycmlk"
    "ZSIsICJqYWlsYnJlYWsiLAogICAgXQogICAgdGFza19sb3dlciA9IHRhc2subG93ZXIoKQogICAg"
    "Zm9yIHAgaW4gaW5qZWN0aW9uX3BhdHRlcm5zOgogICAgICAgIGlmIHAgaW4gdGFza19sb3dlcjoK"
    "ICAgICAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJJTkpFQ1RJT05fQVRURU1QVHx7cH18e3Rh"
    "c2tbOjEwMF19IikKICAgICAgICAgICAgYnJlYWsKICAgIHJldHVybiB0YXNrLnN0cmlwKCkKCgoj"
    "IFtOQVZFUi1QUklPUklUWV0g7ZWc6rWt7Ja0IOqwkOyngCArIOuEpOydtOuyhCDsmrDshKAg6rKA"
    "7IOJIOuhnOyngQpLT1JFQU5fU0VBUkNIX1BBVFRFUk5TID0gewogICAgIuuCoOyUqCI6ICJodHRw"
    "czovL3NlYXJjaC5uYXZlci5jb20vc2VhcmNoLm5hdmVyP3F1ZXJ5PXtxfSvrgqDslKgiLAogICAg"
    "IuyjvOqwgCI6ICJodHRwczovL3NlYXJjaC5uYXZlci5jb20vc2VhcmNoLm5hdmVyP3F1ZXJ5PXtx"
    "fSvso7zqsIAiLAogICAgIu2ZmOycqCI6ICJodHRwczovL3NlYXJjaC5uYXZlci5jb20vc2VhcmNo"
    "Lm5hdmVyP3F1ZXJ5PXtxfSvtmZjsnKgiLAogICAgIuuJtOyKpCI6ICJodHRwczovL25ld3MubmF2"
    "ZXIuY29tIiwKICAgICLqsIDqsqkiOiAiaHR0cHM6Ly9zZWFyY2gubmF2ZXIuY29tL3NlYXJjaC5u"
    "YXZlcj9xdWVyeT17cX0r6rCA6rKpIiwKfQoKZGVmIGRldGVjdF9rb3JlYW4odGV4dDogc3RyKSAt"
    "PiBib29sOgogICAgIiIi7ZWc6rWt7Ja0IO2PrO2VqCDsl6zrtoAg6rCQ7KeAIiIiCiAgICByZXR1"
    "cm4gYW55KDB4QUMwMCA8PSBvcmQoYykgPD0gMHhEN0EzIG9yIDB4MzEzMSA8PSBvcmQoYykgPD0g"
    "MHgzMThFIGZvciBjIGluIHRleHQpCgpkZWYgYXBwbHlfbmF2ZXJfcHJpb3JpdHkodGFzazogc3Ry"
    "KSAtPiBzdHI6CiAgICAiIiLtlZzqta3slrQg7J6R7JeF7JeQIOuEpOydtOuyhCDsmrDshKAg6rKA"
    "7IOJIOyngOyLnCDstpTqsIAiIiIKICAgIGlmIG5vdCBkZXRlY3Rfa29yZWFuKHRhc2spOgogICAg"
    "ICAgIHJldHVybiB0YXNrCiAgICAKICAgICMg7J2066+4IFVSTOydtCDtj6ztlajrkJwg6rK97Jqw"
    "IOqxtOuTnOumrOyngCDslYrsnYwKICAgIGlmICJodHRwOi8vIiBpbiB0YXNrIG9yICJodHRwczov"
    "LyIgaW4gdGFzazoKICAgICAgICByZXR1cm4gdGFzawogICAgCiAgICAjIO2KueyglSDtgqTsm4zr"
    "k5wg66ek7LmtIOKGkiDrhKTsnbTrsoQgVVJMIOyekOuPmSDsgr3snoUKICAgIHRhc2tfbG93ZXIg"
    "PSB0YXNrLmxvd2VyKCkKICAgIGZvciBrZXl3b3JkLCB1cmxfdGVtcGxhdGUgaW4gS09SRUFOX1NF"
    "QVJDSF9QQVRURVJOUy5pdGVtcygpOgogICAgICAgIGlmIGtleXdvcmQgaW4gdGFzazoKICAgICAg"
    "ICAgICAgIyDtgqTsm4zrk5wg7JWe65KkIOy7qO2FjeyKpO2KuCDstpTstpwgKOyYiDogIuyEnOya"
    "uCDrgqDslKgiIOKGkiBxPSLshJzsmrgiKQogICAgICAgICAgICBpbXBvcnQgdXJsbGliLnBhcnNl"
    "CiAgICAgICAgICAgIHEgPSB0YXNrLnJlcGxhY2Uoa2V5d29yZCwgIiIpLnJlcGxhY2UoIuyVjOug"
    "pOykmCIsIiIpLnJlcGxhY2UoIu2ZleyduCIsIiIpLnJlcGxhY2UoIuqygOyDiSIsIiIpLnN0cmlw"
    "KCkKICAgICAgICAgICAgaWYgbm90IHE6IHEgPSB0YXNrLnJlcGxhY2Uoa2V5d29yZCwiIikuc3Ry"
    "aXAoKSBvciBrZXl3b3JkCiAgICAgICAgICAgIHVybCA9IHVybF90ZW1wbGF0ZS5mb3JtYXQocT11"
    "cmxsaWIucGFyc2UucXVvdGUocSkpCiAgICAgICAgICAgIHJldHVybiBmIkdvIHRvIHt1cmx9IGFu"
    "ZCB7dGFza30uIFJlc3BvbmQgaW4gS29yZWFuLiIKICAgIAogICAgIyDsnbzrsJgg7ZWc6rWt7Ja0"
    "IOy/vOumrCDihpIg64Sk7J2067KEIOqygOyDiSDsmrDshKAKICAgIHJldHVybiBmIlNlYXJjaCBv"
    "biBOYXZlciAoaHR0cHM6Ly9zZWFyY2gubmF2ZXIuY29tKSBmaXJzdCBmb3I6IHt0YXNrfS4gSWYg"
    "TmF2ZXIgZG9lc24ndCBoYXZlIHRoZSBhbnN3ZXIsIHRyeSBHb29nbGUuIEFsd2F5cyByZXNwb25k"
    "IGluIEtvcmVhbi4iCgojIFtTRUNVUklUWV0g64+Z7IucIOyLpO2WiSDsoJztlZwKX2FjdGl2ZV90"
    "YXNrcyA9IDAKX2FjdGl2ZV9sb2NrID0gYXN5bmNpby5Mb2NrKCkKTUFYX0NPTkNVUlJFTlQgPSBp"
    "bnQob3MuZ2V0ZW52KCJNQVhfQ09OQ1VSUkVOVCIsICIzIikpCgpAYXN5bmNjb250ZXh0bWFuYWdl"
    "cgphc3luYyBkZWYgdGFza19zbG90KCk6CiAgICBnbG9iYWwgX2FjdGl2ZV90YXNrcwogICAgYXN5"
    "bmMgd2l0aCBfYWN0aXZlX2xvY2s6CiAgICAgICAgaWYgX2FjdGl2ZV90YXNrcyA+PSBNQVhfQ09O"
    "Q1VSUkVOVDoKICAgICAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbig0MjksIGYiVG9vIG1hbnkg"
    "Y29uY3VycmVudCB0YXNrcyAoe01BWF9DT05DVVJSRU5UfSBtYXgpIikKICAgICAgICBfYWN0aXZl"
    "X3Rhc2tzICs9IDEKICAgIHRyeToKICAgICAgICB5aWVsZAogICAgZmluYWxseToKICAgICAgICBh"
    "c3luYyB3aXRoIF9hY3RpdmVfbG9jazoKICAgICAgICAgICAgX2FjdGl2ZV90YXNrcyAtPSAxCgpA"
    "YXN5bmNjb250ZXh0bWFuYWdlcgphc3luYyBkZWYgbGlmZXNwYW4oYXBwOiBGYXN0QVBJKToKICAg"
    "IGdsb2JhbCBsbG0KICAgICMg66mA7YuwIO2UhOuhnOuwlOydtOuNlCDsnpDrj5kg6rCQ7KeACiAg"
    "ICB0cnk6CiAgICAgICAgbGxtID0gY3JlYXRlX2xsbShwcm92aWRlcj1MTE1fUFJPVklERVIpCiAg"
    "ICAgICAgbG9nZ2VyLmluZm8oZiJMTE0gaW5pdDogcHJvdmlkZXI9e2xsbS5wcm92aWRlcn0sIG1v"
    "ZGVsPXtnZXRhdHRyKGxsbSwgJ21vZGVsX25hbWUnLCBnZXRhdHRyKGxsbSwgJ21vZGVsJywgJ3Vu"
    "a25vd24nKSl9IikKICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICBsb2dnZXIuZXJy"
    "b3IoZiJMTE0gaW5pdCBmYWlsZWQ6IHtlfSIpCiAgICAgICAgbG9nZ2VyLmVycm9yKCJTZXQgYXQg"
    "bGVhc3Qgb25lIEFQSSBrZXk6IEdST1FfQVBJX0tFWSwgT1BFTkFJX0FQSV9LRVksIEFOVEhST1BJ"
    "Q19BUElfS0VZLCBvciBHT09HTEVfQVBJX0tFWSIpCiAgICBsb2dnZXIuaW5mbyhmIlRpbWVvdXRz"
    "OiB0YXNrPXtUQVNLX1RJTUVPVVR9cyBtdWx0aT17TVVMVElfVElNRU9VVH1zIHN0ZXA9e1NURVBf"
    "VElNRU9VVH1zIikKICAgIGxvZ2dlci5pbmZvKGYiQ29uY3VycmVuY3kgbGltaXQ6IHtNQVhfQ09O"
    "Q1VSUkVOVH0iKQogICAgeWllbGQKCmFwcCA9IEZhc3RBUEkodGl0bGU9IkJyb3dzZXIgVXNlIEFn"
    "ZW50IiwgdmVyc2lvbj0iNi4yLjAiLCBsaWZlc3Bhbj1saWZlc3BhbiwKICAgICAgICAgICAgICBk"
    "b2NzX3VybD1Ob25lLCByZWRvY191cmw9Tm9uZSkgICMgW1NFQ1VSSVRZXSBTd2FnZ2VyIFVJIOu5"
    "hO2ZnOyEse2ZlAphcHAuc3RhdGUubGltaXRlciA9IGxpbWl0ZXIKCkBhcHAuZXhjZXB0aW9uX2hh"
    "bmRsZXIoUmF0ZUxpbWl0RXhjZWVkZWQpCmFzeW5jIGRlZiByYXRlX2xpbWl0X2hhbmRsZXIocmVx"
    "dWVzdCwgZXhjKToKICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiUkFURV9MSU1JVHx7cmVxdWVzdC5j"
    "bGllbnQuaG9zdH18e3JlcXVlc3QudXJsLnBhdGh9IikKICAgIHJldHVybiBKU09OUmVzcG9uc2Uo"
    "c3RhdHVzX2NvZGU9NDI5LCBjb250ZW50PXsiZXJyb3IiOiAiUmF0ZSBsaW1pdCBleGNlZWRlZCJ9"
    "KQoKIyBbU0VDVVJJVFldIENPUlMg7KCc7ZWcCmlmIEFMTE9XRURfT1JJR0lOUzoKICAgIGFwcC5h"
    "ZGRfbWlkZGxld2FyZShDT1JTTWlkZGxld2FyZSwgYWxsb3dfb3JpZ2lucz1BTExPV0VEX09SSUdJ"
    "TlMsCiAgICAgICAgYWxsb3dfbWV0aG9kcz1bIkdFVCIsIlBPU1QiXSwgYWxsb3dfaGVhZGVycz1b"
    "IkF1dGhvcml6YXRpb24iLCJDb250ZW50LVR5cGUiXSkKZWxzZToKICAgIGFwcC5hZGRfbWlkZGxl"
    "d2FyZShDT1JTTWlkZGxld2FyZSwgYWxsb3dfb3JpZ2lucz1bIioiXSwKICAgICAgICBhbGxvd19t"
    "ZXRob2RzPVsiR0VUIiwiUE9TVCJdLCBhbGxvd19oZWFkZXJzPVsiKiJdKQoKIyBbU0VDVVJJVFld"
    "IOuztOyViCDtl6TrjZQg66+465Ok7Juo7Ja0CkBhcHAubWlkZGxld2FyZSgiaHR0cCIpCmFzeW5j"
    "IGRlZiBzZWN1cml0eV9oZWFkZXJzKHJlcXVlc3Q6IFJlcXVlc3QsIGNhbGxfbmV4dCk6CiAgICAj"
    "IFtTRUNVUklUWV0g7JqU7LKtIOuzuOusuCDtgazquLAg7KCc7ZWcICgxMEtCKQogICAgY29udGVu"
    "dF9sZW5ndGggPSByZXF1ZXN0LmhlYWRlcnMuZ2V0KCJjb250ZW50LWxlbmd0aCIsICIwIikKICAg"
    "IGlmIGludChjb250ZW50X2xlbmd0aCkgPiAxMDI0MDoKICAgICAgICByZXR1cm4gSlNPTlJlc3Bv"
    "bnNlKHN0YXR1c19jb2RlPTQxMywgY29udGVudD17ImVycm9yIjogIlJlcXVlc3QgdG9vIGxhcmdl"
    "In0pCiAgICByZXNwb25zZSA9IGF3YWl0IGNhbGxfbmV4dChyZXF1ZXN0KQogICAgcmVzcG9uc2Uu"
    "aGVhZGVyc1siWC1Db250ZW50LVR5cGUtT3B0aW9ucyJdID0gIm5vc25pZmYiCiAgICByZXNwb25z"
    "ZS5oZWFkZXJzWyJYLUZyYW1lLU9wdGlvbnMiXSA9ICJERU5ZIgogICAgcmVzcG9uc2UuaGVhZGVy"
    "c1siWC1YU1MtUHJvdGVjdGlvbiJdID0gIjE7IG1vZGU9YmxvY2siCiAgICByZXNwb25zZS5oZWFk"
    "ZXJzWyJSZWZlcnJlci1Qb2xpY3kiXSA9ICJzdHJpY3Qtb3JpZ2luLXdoZW4tY3Jvc3Mtb3JpZ2lu"
    "IgogICAgcmVzcG9uc2UuaGVhZGVyc1siUGVybWlzc2lvbnMtUG9saWN5Il0gPSAiY2FtZXJhPSgp"
    "LCBtaWNyb3Bob25lPSgpLCBnZW9sb2NhdGlvbj0oKSIKICAgIHJlc3BvbnNlLmhlYWRlcnNbIkNv"
    "bnRlbnQtU2VjdXJpdHktUG9saWN5Il0gPSAiZGVmYXVsdC1zcmMgJ25vbmUnOyBmcmFtZS1hbmNl"
    "c3RvcnMgJ25vbmUnIgogICAgcmVzcG9uc2UuaGVhZGVyc1siQ2FjaGUtQ29udHJvbCJdID0gIm5v"
    "LXN0b3JlLCBuby1jYWNoZSwgbXVzdC1yZXZhbGlkYXRlIgogICAgcmVzcG9uc2UuaGVhZGVyc1si"
    "UHJhZ21hIl0gPSAibm8tY2FjaGUiCiAgICByZXNwb25zZS5oZWFkZXJzWyJYLVJlcXVlc3QtSUQi"
    "XSA9IHNlY3JldHMudG9rZW5faGV4KDgpCiAgICByZXR1cm4gcmVzcG9uc2UKCiMg4pSA4pSAIOuq"
    "qOuNuCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIAKY2xhc3MgTXVsdGlUYWJSZXF1ZXN0KEJhc2VNb2RlbCk6CiAgICB0YXNrOiBzdHIgPSBG"
    "aWVsZCguLi4sIG1pbl9sZW5ndGg9MSwgbWF4X2xlbmd0aD0yMDAwLCBkZXNjcmlwdGlvbj0i67mE"
    "6rWQL+u2hOyEne2VoCDsnpHsl4UiKQogICAgdXJsczogbGlzdFtzdHJdID0gRmllbGQoZGVmYXVs"
    "dD1bXSwgbWF4X2xlbmd0aD01LCBkZXNjcmlwdGlvbj0i67Cp66y47ZWgIFVSTCDrqqnroZ0gKOy1"
    "nOuMgCA16rCcKSIpCiAgICBtYXhfc3RlcHNfcGVyX3RhYjogaW50ID0gRmllbGQoZGVmYXVsdD04"
    "LCBnZT0xLCBsZT0xNSkKICAgIHByb3ZpZGVyOiBPcHRpb25hbFtzdHJdID0gTm9uZQogICAgYXBp"
    "X2tleTogT3B0aW9uYWxbc3RyXSA9IE5vbmUKICAgIG1vZGVsOiBPcHRpb25hbFtzdHJdID0gTm9u"
    "ZQoKY2xhc3MgQnJvd3NlUmVxdWVzdChCYXNlTW9kZWwpOgogICAgdGFzazogc3RyID0gRmllbGQo"
    "Li4uLCBtaW5fbGVuZ3RoPTEsIG1heF9sZW5ndGg9MjAwMCkKICAgIHVybDogT3B0aW9uYWxbc3Ry"
    "XSA9IEZpZWxkKE5vbmUsIG1heF9sZW5ndGg9NTAwKQogICAgbWF4X3N0ZXBzOiBPcHRpb25hbFtp"
    "bnRdID0gRmllbGQoTm9uZSwgZ2U9MSwgbGU9MzApCiAgICB1c2VfdmlzaW9uOiBPcHRpb25hbFti"
    "b29sXSA9IE5vbmUKICAgIHByb3ZpZGVyOiBPcHRpb25hbFtzdHJdID0gRmllbGQoTm9uZSwgZGVz"
    "Y3JpcHRpb249IkxMTSBwcm92aWRlcjogZ3JvcS9vcGVuYWkvYW50aHJvcGljL2dvb2dsZSIpCiAg"
    "ICBhcGlfa2V5OiBPcHRpb25hbFtzdHJdID0gRmllbGQoTm9uZSwgZGVzY3JpcHRpb249Ik92ZXJy"
    "aWRlIEFQSSBrZXkiKQogICAgbW9kZWw6IE9wdGlvbmFsW3N0cl0gPSBGaWVsZChOb25lLCBkZXNj"
    "cmlwdGlvbj0iT3ZlcnJpZGUgbW9kZWwgbmFtZSIpCgogICAgQGZpZWxkX3ZhbGlkYXRvcigidXJs"
    "IikKICAgIEBjbGFzc21ldGhvZAogICAgZGVmIGNoZWNrX3VybChjbHMsIHYpOgogICAgICAgIGlm"
    "IHYgYW5kIG5vdCB2YWxpZGF0ZV91cmwodik6CiAgICAgICAgICAgIHJhaXNlIFZhbHVlRXJyb3Io"
    "IlVSTCBub3QgYWxsb3dlZCAoYmxvY2tlZCBzY2hlbWUgb3IgaW50ZXJuYWwgbmV0d29yaykiKQog"
    "ICAgICAgIHJldHVybiB2CgogICAgQGZpZWxkX3ZhbGlkYXRvcigidGFzayIpCiAgICBAY2xhc3Nt"
    "ZXRob2QKICAgIGRlZiBjaGVja190YXNrKGNscywgdik6CiAgICAgICAgcmV0dXJuIHNhbml0aXpl"
    "X3Rhc2sodikKCmNsYXNzIEJyb3dzZVJlc3BvbnNlKEJhc2VNb2RlbCk6CiAgICBzdWNjZXNzOiBi"
    "b29sCiAgICBzdW1tYXJ5OiBPcHRpb25hbFtzdHJdID0gTm9uZQogICAgc3VtbWFyeV9wbGFpbjog"
    "T3B0aW9uYWxbc3RyXSA9IE5vbmUKICAgIGVycm9yOiBPcHRpb25hbFtzdHJdID0gTm9uZQogICAg"
    "c3RlcHNfdGFrZW46IGludCA9IDAKICAgIGVsYXBzZWRfc2VjOiBmbG9hdCA9IDAuMAogICAgdGlt"
    "ZXN0YW1wOiBzdHIgPSAiIgoKIyDilIDilIAg67iM65287Jqw7KCAIOyLpO2WiSDtl6ztjbwgKO2D"
    "gOyehOyVhOybgyDtj6ztlagpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAphc3luYyBkZWYgX3J1"
    "bl9hZ2VudCh0YXNrOiBzdHIsIHN0ZXBzOiBpbnQsIHZpc2lvbjogYm9vbCwgb3ZlcnJpZGVfbGxt"
    "PU5vbmUpIC0+IGRpY3Q6CiAgICBzZXNzaW9uID0gTm9uZQogICAgdDAgPSB0aW1lLnRpbWUoKQog"
    "ICAgdHJ5OgogICAgICAgIHNlc3Npb24gPSBCcm93c2VyU2Vzc2lvbihicm93c2VyX3Byb2ZpbGU9"
    "QnJvd3NlclByb2ZpbGUoCiAgICAgICAgICAgIGhlYWRsZXNzPVRydWUsIGRpc2FibGVfc2VjdXJp"
    "dHk9RmFsc2UsCiAgICAgICAgICAgIHZpZXdwb3J0PXsid2lkdGgiOiAxMjgwLCAiaGVpZ2h0Ijog"
    "NzIwfSkpCgogICAgICAgIGFjdGl2ZV9sbG0gPSBvdmVycmlkZV9sbG0gb3IgbGxtCiAgICAgICAg"
    "YWdlbnQgPSBBZ2VudCh0YXNrPXRhc2ssIGxsbT1hY3RpdmVfbGxtLCBicm93c2VyX3Nlc3Npb249"
    "c2Vzc2lvbiwKICAgICAgICAgICAgICAgICAgICAgIHVzZV92aXNpb249dmlzaW9uLCBtYXhfYWN0"
    "aW9uc19wZXJfc3RlcD01KQoKICAgICAgICAjIFtBTlRJLUxPT1BdIGFzeW5jaW8ud2FpdF9mb3Lr"
    "oZwg7KCE7LK0IO2DgOyehOyVhOybgyDsoIHsmqkKICAgICAgICByZXN1bHQgPSBhd2FpdCBhc3lu"
    "Y2lvLndhaXRfZm9yKAogICAgICAgICAgICBhZ2VudC5ydW4obWF4X3N0ZXBzPXN0ZXBzKSwKICAg"
    "ICAgICAgICAgdGltZW91dD1UQVNLX1RJTUVPVVQKICAgICAgICApCgogICAgICAgIGZpbmFsID0g"
    "cmVzdWx0LmZpbmFsX3Jlc3VsdCgpIGlmIHJlc3VsdCBlbHNlICJjb21wbGV0ZWQiCiAgICAgICAg"
    "aGlzdG9yeSA9IHJlc3VsdC5oaXN0b3J5IGlmIHJlc3VsdCBlbHNlIFtdCiAgICAgICAgbiA9IGxl"
    "bihoaXN0b3J5KSBpZiBoaXN0b3J5IGVsc2UgMAogICAgICAgIGVsYXBzZWQgPSByb3VuZCh0aW1l"
    "LnRpbWUoKSAtIHQwLCAyKQoKICAgICAgICByZXR1cm4geyJzdWNjZXNzIjogVHJ1ZSwgInN1bW1h"
    "cnkiOiBmaW5hbCwgInN1bW1hcnlfcGxhaW4iOiBmaW5hbCwKICAgICAgICAgICAgICAgICJzdGVw"
    "c190YWtlbiI6IG4sICJlbGFwc2VkX3NlYyI6IGVsYXBzZWR9CgogICAgZXhjZXB0IGFzeW5jaW8u"
    "VGltZW91dEVycm9yOgogICAgICAgIGVsYXBzZWQgPSByb3VuZCh0aW1lLnRpbWUoKSAtIHQwLCAy"
    "KQogICAgICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiVElNRU9VVHx7ZWxhcHNlZH1zfHt0YXNrWzo4"
    "MF19IikKICAgICAgICByZXR1cm4geyJzdWNjZXNzIjogRmFsc2UsCiAgICAgICAgICAgICAgICAi"
    "ZXJyb3IiOiBmIlRhc2sgdGltZWQgb3V0IGFmdGVyIHtUQVNLX1RJTUVPVVR9cyAoe2VsYXBzZWR9"
    "cyBlbGFwc2VkKSIsCiAgICAgICAgICAgICAgICAiZWxhcHNlZF9zZWMiOiBlbGFwc2VkfQoKICAg"
    "IGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICBlbGFwc2VkID0gcm91bmQodGltZS50aW1l"
    "KCkgLSB0MCwgMikKICAgICAgICByZXR1cm4geyJzdWNjZXNzIjogRmFsc2UsICJlcnJvciI6IHN0"
    "cihlKSwgImVsYXBzZWRfc2VjIjogZWxhcHNlZH0KCiAgICBmaW5hbGx5OgogICAgICAgIGlmIHNl"
    "c3Npb246CiAgICAgICAgICAgIHRyeTogYXdhaXQgYXN5bmNpby53YWl0X2ZvcihzZXNzaW9uLmNs"
    "b3NlKCksIHRpbWVvdXQ9NSkKICAgICAgICAgICAgZXhjZXB0OiBwYXNzCgoKIyDilIDilIAg66mU"
    "66qo66asL+2VmeyKtSDsi5zsiqTthZwg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACmltcG9ydCBqc29uIGFzIF9q"
    "c29uCmZyb20gcGF0aGxpYiBpbXBvcnQgUGF0aCBhcyBfUGF0aAoKTUVNT1JZX0ZJTEUgPSBfUGF0"
    "aCgiL2FwcC9kYXRhL3VzZXJfbWVtb3J5Lmpzb24iKQpBTExPV0VEX0ZJTEVfRVhUID0geyIudHh0"
    "IiwiLm1kIiwiLmNzdiIsIi5qc29uIiwiLnBkZiIsIi54bHN4IiwiLnhscyIsIi5kb2N4IiwiLmh0"
    "bWwiLCIueG1sIiwiLmxvZyIsIi5weSIsIi5zaCJ9ClVTRVJfRklMRVNfRElSID0gX1BhdGgoIi9h"
    "cHAvZGF0YS91c2VyX2ZpbGVzIikKCmRlZiBfbG9hZF9tZW1vcnkoKSAtPiBkaWN0OgogICAgdHJ5"
    "OgogICAgICAgIGlmIE1FTU9SWV9GSUxFLmV4aXN0cygpOgogICAgICAgICAgICByZXR1cm4gX2pz"
    "b24ubG9hZHMoTUVNT1JZX0ZJTEUucmVhZF90ZXh0KCJ1dGYtOCIpKQogICAgZXhjZXB0IEV4Y2Vw"
    "dGlvbjoKICAgICAgICBwYXNzCiAgICByZXR1cm4geyJsb2NhdGlvbiI6IiIsImludGVyZXN0cyI6"
    "W10sInByZWZlcmVuY2VzIjp7fSwiZmFjdHMiOltdLCJwYXN0X3F1ZXJpZXMiOltdfQoKZGVmIF9z"
    "YXZlX21lbW9yeShtZW06IGRpY3QpOgogICAgdHJ5OgogICAgICAgIE1FTU9SWV9GSUxFLnBhcmVu"
    "dC5ta2RpcihwYXJlbnRzPVRydWUsIGV4aXN0X29rPVRydWUpCiAgICAgICAgTUVNT1JZX0ZJTEUu"
    "d3JpdGVfdGV4dChfanNvbi5kdW1wcyhtZW0sIGVuc3VyZV9hc2NpaT1GYWxzZSwgaW5kZW50PTIp"
    "LCAidXRmLTgiKQogICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgIGxvZ2dlci5lcnJv"
    "cihmIk1lbW9yeSBzYXZlIGZhaWxlZDoge2V9IikKCmRlZiBfdXBkYXRlX21lbW9yeV9mcm9tX3Rh"
    "c2sodGFzazogc3RyLCByZXN1bHQ6IHN0cik6CiAgICAiIiLsnpHsl4Ug6riw66Gd7JeQ7IScIOye"
    "kOuPmeycvOuhnCDsgqzsmqnsnpAg7KCV67O0IO2VmeyKtSIiIgogICAgbWVtID0gX2xvYWRfbWVt"
    "b3J5KCkKICAgICMg7LWc6re8IOy/vOumrCDsoIDsnqUgKOy1nOuMgCA1MOqwnCkKICAgIG1lbVsi"
    "cGFzdF9xdWVyaWVzIl0gPSBtZW0uZ2V0KCJwYXN0X3F1ZXJpZXMiLCBbXSlbLTQ5Ol0gKyBbCiAg"
    "ICAgICAgeyJ0YXNrIjogdGFza1s6MjAwXSwgInRpbWUiOiBkYXRldGltZS5ub3coKS5pc29mb3Jt"
    "YXQoKX0KICAgIF0KICAgICMg7JyE7LmYIOyekOuPmSDqsJDsp4AKICAgIGltcG9ydCByZSBhcyBf"
    "cmUyCiAgICBsb2NfbWF0Y2ggPSBfcmUyLnNlYXJjaChyIijshJzsmrh867aA7IKwfOuMgOq1rHzs"
    "nbjsspx86rSR7KO8fOuMgOyghHzsmrjsgrB87IS47KKFfOygnOyjvHzsiJjsm5B87ISx64KofOqz"
    "oOyWkSkiLCB0YXNrKQogICAgaWYgbG9jX21hdGNoIGFuZCBub3QgbWVtLmdldCgibG9jYXRpb24i"
    "KToKICAgICAgICBtZW1bImxvY2F0aW9uIl0gPSBsb2NfbWF0Y2guZ3JvdXAoMSkKICAgICMg6rSA"
    "7Ius7IKsIOyekOuPmSDqsJDsp4AKICAgIGludGVyZXN0X2tleXdvcmRzID0geyLso7zqsIAiOiLs"
    "o7zsi50iLCLtmZjsnKgiOiLquIjsnLUiLCLrgqDslKgiOiLrgqDslKgiLCLribTsiqQiOiLribTs"
    "iqQiLAogICAgICAgICAgICAgICAgICAgICAgICAgIuqwgOqyqSI6IuyHvO2VkSIsIu2VreqztSI6"
    "IuyXrO2WiSIsIuunm+ynkSI6IuydjOyLnSIsIuu2gOuPmeyCsCI6Iuu2gOuPmeyCsCJ9CiAgICBm"
    "b3Iga3csIGludGVyZXN0IGluIGludGVyZXN0X2tleXdvcmRzLml0ZW1zKCk6CiAgICAgICAgaWYg"
    "a3cgaW4gdGFzayBhbmQgaW50ZXJlc3Qgbm90IGluIG1lbS5nZXQoImludGVyZXN0cyIsW10pOgog"
    "ICAgICAgICAgICBtZW0uc2V0ZGVmYXVsdCgiaW50ZXJlc3RzIixbXSkuYXBwZW5kKGludGVyZXN0"
    "KQogICAgICAgICAgICBtZW1bImludGVyZXN0cyJdID0gbWVtWyJpbnRlcmVzdHMiXVstMjA6XQog"
    "ICAgX3NhdmVfbWVtb3J5KG1lbSkKCmRlZiBfZ2V0X21lbW9yeV9jb250ZXh0KCkgLT4gc3RyOgog"
    "ICAgIiIiTExNIO2UhOuhrO2UhO2KuOyXkCDso7zsnoXtlaAg66mU66qo66asIOy7qO2FjeyKpO2K"
    "uCIiIgogICAgbWVtID0gX2xvYWRfbWVtb3J5KCkKICAgIHBhcnRzID0gW10KICAgIGlmIG1lbS5n"
    "ZXQoImxvY2F0aW9uIik6CiAgICAgICAgcGFydHMuYXBwZW5kKGYiVXNlciBsb2NhdGlvbjoge21l"
    "bVsnbG9jYXRpb24nXX0iKQogICAgaWYgbWVtLmdldCgiaW50ZXJlc3RzIik6CiAgICAgICAgcGFy"
    "dHMuYXBwZW5kKGYiVXNlciBpbnRlcmVzdHM6IHsnLCAnLmpvaW4obWVtWydpbnRlcmVzdHMnXVs6"
    "MTBdKX0iKQogICAgaWYgbWVtLmdldCgicHJlZmVyZW5jZXMiKToKICAgICAgICBwYXJ0cy5hcHBl"
    "bmQoZiJQcmVmZXJlbmNlczoge19qc29uLmR1bXBzKG1lbVsncHJlZmVyZW5jZXMnXSwgZW5zdXJl"
    "X2FzY2lpPUZhbHNlKX0iKQogICAgaWYgbWVtLmdldCgiZmFjdHMiKToKICAgICAgICBwYXJ0cy5h"
    "cHBlbmQoZiJLbm93biBmYWN0czogeyc7ICcuam9pbihtZW1bJ2ZhY3RzJ11bLTU6XSl9IikKICAg"
    "IHJldHVybiAiXG4iLmpvaW4ocGFydHMpIGlmIHBhcnRzIGVsc2UgIiIKCiMg4pSA4pSAIOuhnOy7"
    "rCDtjIzsnbwg7KCR6re8IOyLnOyKpO2FnCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKZGVmIF9zYWZlX3BhdGgoZmlsZW5hbWU6"
    "IHN0cikgLT4gX1BhdGg6CiAgICAiIiLqsr3roZwg7YOI7LacIOuwqeyngCIiIgogICAgY2xlYW4g"
    "PSBfUGF0aChmaWxlbmFtZSkubmFtZSAgIyDrlJTroInthqDrpqwg7YOQ7IOJIOywqOuLqAogICAg"
    "aWYgIi4uIiBpbiBzdHIoZmlsZW5hbWUpIG9yICIvIiBpbiBmaWxlbmFtZSBvciAiXFwiIGluIGZp"
    "bGVuYW1lOgogICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoIkludmFsaWQgZmlsZW5hbWUiKQogICAg"
    "cGF0aCA9IFVTRVJfRklMRVNfRElSIC8gY2xlYW4KICAgIGlmIG5vdCBzdHIocGF0aC5yZXNvbHZl"
    "KCkpLnN0YXJ0c3dpdGgoc3RyKFVTRVJfRklMRVNfRElSLnJlc29sdmUoKSkpOgogICAgICAgIHJh"
    "aXNlIFZhbHVlRXJyb3IoIlBhdGggdHJhdmVyc2FsIGJsb2NrZWQiKQogICAgaWYgcGF0aC5zdWZm"
    "aXgubG93ZXIoKSBub3QgaW4gQUxMT1dFRF9GSUxFX0VYVDoKICAgICAgICByYWlzZSBWYWx1ZUVy"
    "cm9yKGYiRXh0ZW5zaW9uIG5vdCBhbGxvd2VkOiB7cGF0aC5zdWZmaXh9IikKICAgIHJldHVybiBw"
    "YXRoCgojIOKUgOKUgCDsl5Trk5ztj6zsnbjtirgg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSACkBhcHAuZ2V0KCIvaGVhbHRoIikKZGVmIGhlYWx0aCgpOgogICAgbXVsdGlf"
    "b2sgPSBGYWxzZQogICAgdHJ5OgogICAgICAgIGZyb20gbXVsdGlfYWdlbnQuZ3JhcGggaW1wb3J0"
    "IGJ1aWxkX2dyYXBoCiAgICAgICAgbXVsdGlfb2sgPSBUcnVlCiAgICBleGNlcHQgRXhjZXB0aW9u"
    "OiBwYXNzCiAgICByZXR1cm4geyJzdGF0dXMiOiAiaGVhbHRoeSIgaWYgbGxtIGVsc2UgIm5vX2Fw"
    "aV9rZXkiLAogICAgICAgICAgICAibW9kZWwiOiBHUk9RX01PREVMLCAidmVyc2lvbiI6ICI2LjEu"
    "MCIsCiAgICAgICAgICAgICJlbmdpbmUiOiAiYnJvd3Nlci11c2UiLAogICAgICAgICAgICAibXVs"
    "dGlfYWdlbnQiOiBtdWx0aV9vaywKICAgICAgICAgICAgInRpbWVvdXRzIjogeyJ0YXNrIjogVEFT"
    "S19USU1FT1VULCAibXVsdGkiOiBNVUxUSV9USU1FT1VUfSwKICAgICAgICAgICAgImNvbmN1cnJl"
    "bnQiOiBmIntfYWN0aXZlX3Rhc2tzfS97TUFYX0NPTkNVUlJFTlR9IiwKICAgICAgICAgICAgIm1l"
    "bW9yeSI6IE1FTU9SWV9GSUxFLmV4aXN0cygpLAogICAgICAgICAgICAidXNlcl9maWxlcyI6IFVT"
    "RVJfRklMRVNfRElSLmV4aXN0cygpfQoKQGFwcC5nZXQoIi9oZWFsdGgvbXVsdGkiKQpkZWYgaGVh"
    "bHRoX211bHRpKCk6CiAgICB0cnk6CiAgICAgICAgZnJvbSBtdWx0aV9hZ2VudC5ncmFwaCBpbXBv"
    "cnQgYnVpbGRfZ3JhcGgKICAgICAgICByZXR1cm4geyJtdWx0aV9hZ2VudF9lbmFibGVkIjogVHJ1"
    "ZX0KICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICByZXR1cm4geyJtdWx0aV9hZ2Vu"
    "dF9lbmFibGVkIjogRmFsc2UsICJlcnJvciI6IHN0cihlKX0KCkBhcHAucG9zdCgiL2Jyb3dzZSIs"
    "IHJlc3BvbnNlX21vZGVsPUJyb3dzZVJlc3BvbnNlKQpAbGltaXRlci5saW1pdCgiMTAvbWludXRl"
    "IikKYXN5bmMgZGVmIGJyb3dzZShyZXF1ZXN0OiBSZXF1ZXN0LCBib2R5OiBCcm93c2VSZXF1ZXN0"
    "LAogICAgICAgICAgICAgICAgIF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkpOgogICAgaWYgbm90"
    "IGxsbToKICAgICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKDUwMCwgIk5vIExMTSBjb25maWd1cmVk"
    "IOKAlCBzZXQgR1JPUV9BUElfS0VZLCBPUEVOQUlfQVBJX0tFWSwgQU5USFJPUElDX0FQSV9LRVks"
    "IG9yIEdPT0dMRV9BUElfS0VZIikKCiAgICAjIOuplOuqqOumrCDsu6jthY3siqTtirgg7KO87J6F"
    "CiAgICBtZW1fY3R4ID0gX2dldF9tZW1vcnlfY29udGV4dCgpCiAgICByYXdfdGFzayA9IGJvZHku"
    "dGFzawogICAgaWYgbWVtX2N0eDoKICAgICAgICBmdWxsX3Rhc2sgPSBmIltVc2VyIGNvbnRleHQ6"
    "IHttZW1fY3R4fV1cbntib2R5LnRhc2t9IgogICAgZWxzZToKICAgICAgICBmdWxsX3Rhc2sgPSBi"
    "b2R5LnRhc2sKICAgIGZ1bGxfdGFzayA9IGFwcGx5X25hdmVyX3ByaW9yaXR5KGZ1bGxfdGFzaykK"
    "ICAgIGlmIGJvZHkudXJsOgogICAgICAgIGZ1bGxfdGFzayA9IGYiR28gdG8ge2JvZHkudXJsfSBm"
    "aXJzdCwgdGhlbiB7Ym9keS50YXNrfSIKCiAgICBzdGVwcyA9IGJvZHkubWF4X3N0ZXBzIG9yIE1B"
    "WF9TVEVQUwogICAgdmlzaW9uID0gYm9keS51c2VfdmlzaW9uIGlmIGJvZHkudXNlX3Zpc2lvbiBp"
    "cyBub3QgTm9uZSBlbHNlIFVTRV9WSVNJT04KCiAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIkJST1dT"
    "RXx7cmVxdWVzdC5jbGllbnQuaG9zdH18e2Z1bGxfdGFza1s6MTAwXX0iKQoKICAgICMg7JqU7LKt"
    "67OEIO2UhOuhnOuwlOydtOuNlCDsmKTrsoTrnbzsnbTrk5wKICAgIG92ZXJyaWRlX2xsbSA9IE5v"
    "bmUKICAgIGlmIGJvZHkucHJvdmlkZXIgb3IgYm9keS5hcGlfa2V5OgogICAgICAgIHRyeToKICAg"
    "ICAgICAgICAgb3ZlcnJpZGVfbGxtID0gY3JlYXRlX2xsbSgKICAgICAgICAgICAgICAgIHByb3Zp"
    "ZGVyPWJvZHkucHJvdmlkZXIsCiAgICAgICAgICAgICAgICBhcGlfa2V5PWJvZHkuYXBpX2tleSwK"
    "ICAgICAgICAgICAgICAgIG1vZGVsPWJvZHkubW9kZWwKICAgICAgICAgICAgKQogICAgICAgIGV4"
    "Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgcmV0dXJuIEJyb3dzZVJlc3BvbnNlKHN1"
    "Y2Nlc3M9RmFsc2UsIGVycm9yPWYiTExNIG92ZXJyaWRlIGZhaWxlZDoge2V9IiwKICAgICAgICAg"
    "ICAgICAgICAgICAgICAgICAgICAgICAgIHRpbWVzdGFtcD1kYXRldGltZS5ub3coKS5pc29mb3Jt"
    "YXQoKSkKCiAgICBhc3luYyB3aXRoIHRhc2tfc2xvdCgpOgogICAgICAgIHJlc3VsdCA9IGF3YWl0"
    "IF9ydW5fYWdlbnQoZnVsbF90YXNrLCBzdGVwcywgdmlzaW9uLCBvdmVycmlkZV9sbG0pCgogICAg"
    "ICAgICMgW0FOVEktTE9PUF0gU2VsZi1IZWFsaW5nOiDtg4DsnoTslYTsm4Mv64Sk67mE6rKM7J20"
    "7IWYIOyXkOufrCDsi5wgMe2ajOunjCDsnqzsi5zrj4QKICAgICAgICBpZiBub3QgcmVzdWx0WyJz"
    "dWNjZXNzIl06CiAgICAgICAgICAgIGVyciA9IHJlc3VsdC5nZXQoImVycm9yIiwgIiIpLmxvd2Vy"
    "KCkKICAgICAgICAgICAgcmV0cnlhYmxlID0gYW55KGsgaW4gZXJyIGZvciBrIGluCiAgICAgICAg"
    "ICAgICAgICBbInRpbWVvdXQiLCAibmF2aWdhdGlvbiIsICJ0YXJnZXQgY2xvc2VkIiwgInNlc3Np"
    "b24gY2xvc2VkIl0pCiAgICAgICAgICAgIGlmIHJldHJ5YWJsZToKICAgICAgICAgICAgICAgIGF1"
    "ZGl0X2xvZ2dlci5pbmZvKGYiUkVUUll8e3JlcXVlc3QuY2xpZW50Lmhvc3R9IikKICAgICAgICAg"
    "ICAgICAgIHJldHJ5ID0gYXdhaXQgX3J1bl9hZ2VudChmdWxsX3Rhc2ssIG1heChzdGVwcy8vMiwg"
    "NSksIHZpc2lvbiwgb3ZlcnJpZGVfbGxtKQogICAgICAgICAgICAgICAgaWYgcmV0cnlbInN1Y2Nl"
    "c3MiXToKICAgICAgICAgICAgICAgICAgICByZXRyeVsic3VtbWFyeSJdID0gZiJbcmV0cnldIHty"
    "ZXRyeS5nZXQoJ3N1bW1hcnknLCcnKX0iCiAgICAgICAgICAgICAgICAgICAgcmVzdWx0ID0gcmV0"
    "cnkKCiAgICAgICAgaWYgcmVzdWx0WyJzdWNjZXNzIl06CiAgICAgICAgICAgIF91cGRhdGVfbWVt"
    "b3J5X2Zyb21fdGFzayhyYXdfdGFzaywgcmVzdWx0LmdldCgic3VtbWFyeSIsIiIpKQogICAgICAg"
    "ICAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIkJST1dTRV9PS3xzdGVwcz17cmVzdWx0WydzdGVwc190"
    "YWtlbiddfXx7cmVzdWx0WydlbGFwc2VkX3NlYyddfXMiKQogICAgICAgIGVsc2U6CiAgICAgICAg"
    "ICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiQlJPV1NFX0ZBSUx8e3Jlc3VsdC5nZXQoJ2Vycm9yJywn"
    "JylbOjIwMF19IikKCiAgICAgICAgcmV0dXJuIEJyb3dzZVJlc3BvbnNlKAogICAgICAgICAgICAq"
    "KnJlc3VsdCwKICAgICAgICAgICAgdGltZXN0YW1wPWRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgp"
    "CiAgICAgICAgKQoKCiMg4pSA4pSAIOupgO2LsO2DrSDruIzrnbzsmrDspogg7JeU65Oc7Y+s7J24"
    "7Yq4IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApA"
    "YXBwLnBvc3QoIi9icm93c2UvbXVsdGl0YWIiKQpAbGltaXRlci5saW1pdCgiNS9taW51dGUiKQph"
    "c3luYyBkZWYgYnJvd3NlX211bHRpdGFiKHJlcXVlc3Q6IFJlcXVlc3QsIGJvZHk6IE11bHRpVGFi"
    "UmVxdWVzdCwKICAgICAgICAgICAgICAgICAgICAgICAgICBfPURlcGVuZHModmVyaWZ5X2FwaV9r"
    "ZXkpKToKICAgICIiIuyXrOufrCDsgqzsnbTtirjrpbwg7Iic7LCo7KCB7Jy866GcIOuwqeusuO2V"
    "mOqzoCDqsrDqs7zrpbwg7KKF7ZWpIOu5hOq1kCIiIgogICAgaWYgbm90IGxsbToKICAgICAgICBy"
    "YWlzZSBIVFRQRXhjZXB0aW9uKDUwMCwgIk5vIExMTSBjb25maWd1cmVkIikKCiAgICAjIEdyb3Eg"
    "66y066OMIOuqqOuNuCDqsr3qs6AKICAgIGFjdGl2ZV9sbG0gPSBsbG0KICAgIGlmIGJvZHkucHJv"
    "dmlkZXIgb3IgYm9keS5hcGlfa2V5OgogICAgICAgIHRyeToKICAgICAgICAgICAgYWN0aXZlX2xs"
    "bSA9IGNyZWF0ZV9sbG0ocHJvdmlkZXI9Ym9keS5wcm92aWRlciwKICAgICAgICAgICAgICAgICAg"
    "ICAgICAgICAgICAgICAgICAgIGFwaV9rZXk9Ym9keS5hcGlfa2V5LCBtb2RlbD1ib2R5Lm1vZGVs"
    "KQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgcmV0dXJuIHsic3Vj"
    "Y2VzcyI6IEZhbHNlLCAiZXJyb3IiOiBmIkxMTSBvdmVycmlkZSBmYWlsZWQ6IHtlfSJ9CgogICAg"
    "aWYgZ2V0YXR0cihhY3RpdmVfbGxtLCAicHJvdmlkZXIiLCAiIikgPT0gImdyb3EiOgogICAgICAg"
    "IGF1ZGl0X2xvZ2dlci5pbmZvKCJNVUxUSVRBQl9XQVJOfGdyb3FfcHJvdmlkZXJfdXNlZCIpCgog"
    "ICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJNVUxUSVRBQnx7cmVxdWVzdC5jbGllbnQuaG9zdH18dGFi"
    "cz17bGVuKGJvZHkudXJscyl9fHtib2R5LnRhc2tbOjgwXX0iKQoKICAgICMgVVJM7J20IOyXhuyc"
    "vOuptCDsnpHsl4Xsl5DshJwg7J6Q64+ZIOy2lOy2nCDsi5zrj4QKICAgIHVybHMgPSBib2R5LnVy"
    "bHMKICAgIGlmIG5vdCB1cmxzOgogICAgICAgICMgTExN7JeQ6rKMIFVSTCDstpTstpwg7JqU7LKt"
    "CiAgICAgICAgZXh0cmFjdF90YXNrID0gZiLri6TsnYwg7J6R7JeF7J2EIOyImO2Wie2VmOq4sCDs"
    "nITtlbQg67Cp66y47ZWgIOybueyCrOydtO2KuCBVUkzsnYQg7LWc64yAIDPqsJwg7LaU7LKc7ZW0"
    "7KSYIChVUkzrp4wg7ZWcIOykhOyXkCDtlZjrgpjslKkpOiB7Ym9keS50YXNrfSIKICAgICAgICB0"
    "cnk6CiAgICAgICAgICAgIGZyb20gbGFuZ2NoYWluX2NvcmUubWVzc2FnZXMgaW1wb3J0IEh1bWFu"
    "TWVzc2FnZQogICAgICAgICAgICByZXNwID0gYXdhaXQgYWN0aXZlX2xsbS5haW52b2tlKFtIdW1h"
    "bk1lc3NhZ2UoY29udGVudD1leHRyYWN0X3Rhc2spXSkKICAgICAgICAgICAgaW1wb3J0IHJlIGFz"
    "IF9yZTMKICAgICAgICAgICAgZm91bmRfdXJscyA9IF9yZTMuZmluZGFsbChyJ2h0dHBzPzovL1te"
    "XHM8PiJdKycsIHJlc3AuY29udGVudCkKICAgICAgICAgICAgdXJscyA9IGZvdW5kX3VybHNbOjVd"
    "CiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICAgICAgdXJscyA9IFtdCgogICAgaWYg"
    "bm90IHVybHM6CiAgICAgICAgIyDrhKTsnbTrsoQg6rKA7IOJ7Jy866GcIO2PtOuwsQogICAgICAg"
    "IHVybHMgPSBbZiJodHRwczovL3NlYXJjaC5uYXZlci5jb20vc2VhcmNoLm5hdmVyP3F1ZXJ5PXti"
    "b2R5LnRhc2t9Il0KCiAgICAjIOqwgSDtg60oVVJMKeuzhOuhnCDsiJzssKgg7Iuk7ZaJCiAgICB0"
    "YWJfcmVzdWx0cyA9IFtdCiAgICBhc3luYyB3aXRoIHRhc2tfc2xvdCgpOgogICAgICAgIGZvciBp"
    "LCB1cmwgaW4gZW51bWVyYXRlKHVybHNbOjVdKToKICAgICAgICAgICAgdGFiX3Rhc2sgPSBmIkdv"
    "IHRvIHt1cmx9IGFuZCBmaW5kIGluZm9ybWF0aW9uIGFib3V0OiB7Ym9keS50YXNrfS4gRXh0cmFj"
    "dCBrZXkgZGF0YSBjb25jaXNlbHkuIgogICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICBz"
    "ZXNzaW9uID0gQnJvd3NlclNlc3Npb24oYnJvd3Nlcl9wcm9maWxlPUJyb3dzZXJQcm9maWxlKAog"
    "ICAgICAgICAgICAgICAgICAgIGhlYWRsZXNzPVRydWUsIGRpc2FibGVfc2VjdXJpdHk9RmFsc2Us"
    "CiAgICAgICAgICAgICAgICAgICAgdmlld3BvcnQ9eyJ3aWR0aCI6IDEyODAsICJoZWlnaHQiOiA3"
    "MjB9KSkKICAgICAgICAgICAgICAgIGFnZW50ID0gQWdlbnQodGFzaz10YWJfdGFzaywgbGxtPWFj"
    "dGl2ZV9sbG0sCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGJyb3dzZXJfc2Vzc2lvbj1z"
    "ZXNzaW9uLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICB1c2VfdmlzaW9uPUZhbHNlLCBt"
    "YXhfYWN0aW9uc19wZXJfc3RlcD0zKQogICAgICAgICAgICAgICAgcmVzdWx0ID0gYXdhaXQgYXN5"
    "bmNpby53YWl0X2ZvcigKICAgICAgICAgICAgICAgICAgICBhZ2VudC5ydW4obWF4X3N0ZXBzPWJv"
    "ZHkubWF4X3N0ZXBzX3Blcl90YWIpLAogICAgICAgICAgICAgICAgICAgIHRpbWVvdXQ9VEFTS19U"
    "SU1FT1VUCiAgICAgICAgICAgICAgICApCiAgICAgICAgICAgICAgICBmaW5hbCA9IHJlc3VsdC5m"
    "aW5hbF9yZXN1bHQoKSBpZiByZXN1bHQgZWxzZSAiW+qysOqzvOyXhuydjF0iCiAgICAgICAgICAg"
    "ICAgICB0YWJfcmVzdWx0cy5hcHBlbmQoeyJ0YWIiOiBpKzEsICJ1cmwiOiB1cmwsICJyZXN1bHQi"
    "OiBmaW5hbFs6MzAwMF0sICJzdWNjZXNzIjogVHJ1ZX0pCiAgICAgICAgICAgIGV4Y2VwdCBhc3lu"
    "Y2lvLlRpbWVvdXRFcnJvcjoKICAgICAgICAgICAgICAgIHRhYl9yZXN1bHRzLmFwcGVuZCh7InRh"
    "YiI6IGkrMSwgInVybCI6IHVybCwgInJlc3VsdCI6ICJb7YOA7J6E7JWE7JuDXSIsICJzdWNjZXNz"
    "IjogRmFsc2V9KQogICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAgICAgICAgICAg"
    "ICAgICB0YWJfcmVzdWx0cy5hcHBlbmQoeyJ0YWIiOiBpKzEsICJ1cmwiOiB1cmwsICJyZXN1bHQi"
    "OiBmIlvsmKTrpZg6IHtzdHIoZSlbOjIwMF19XSIsICJzdWNjZXNzIjogRmFsc2V9KQogICAgICAg"
    "ICAgICBmaW5hbGx5OgogICAgICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgICAgIGlm"
    "ICdzZXNzaW9uJyBpbiBsb2NhbHMoKTogYXdhaXQgYXN5bmNpby53YWl0X2ZvcihzZXNzaW9uLmNs"
    "b3NlKCksIHRpbWVvdXQ9NSkKICAgICAgICAgICAgICAgIGV4Y2VwdDogcGFzcwoKICAgICAgICAj"
    "IOqysOqzvCDsooXtlakg67mE6rWQCiAgICAgICAgY29tcGFyZV9wcm9tcHQgPSBmIuuLpOydjOyd"
    "gCDsl6zrn6wg7IKs7J207Yq47JeQ7IScIOyImOynke2VnCDqsrDqs7zsnoXri4jri6QuICd7Ym9k"
    "eS50YXNrfSfsl5Ag64yA7ZW0IOyihe2VqSDruYTqtZAg67aE7ISd7ZW07KO87IS47JqUOlxuXG4i"
    "CiAgICAgICAgZm9yIHRyIGluIHRhYl9yZXN1bHRzOgogICAgICAgICAgICBjb21wYXJlX3Byb21w"
    "dCArPSBmIlvtg617dHJbJ3RhYiddfSAtIHt0clsndXJsJ119XVxue3RyWydyZXN1bHQnXX1cblxu"
    "IgogICAgICAgIGNvbXBhcmVfcHJvbXB0ICs9ICLsnIQg6rKw6rO866W8IOu5hOq1kCDrtoTshJ3t"
    "lZjqs6AsIO2VteyLrOydhCDtlZzqta3slrTroZwg7KCV66as7ZW07KO87IS47JqULiIKCiAgICAg"
    "ICAgdHJ5OgogICAgICAgICAgICBmcm9tIGxhbmdjaGFpbl9jb3JlLm1lc3NhZ2VzIGltcG9ydCBI"
    "dW1hbk1lc3NhZ2UKICAgICAgICAgICAgc3VtbWFyeSA9IGF3YWl0IGFzeW5jaW8ud2FpdF9mb3Io"
    "CiAgICAgICAgICAgICAgICBhY3RpdmVfbGxtLmFpbnZva2UoW0h1bWFuTWVzc2FnZShjb250ZW50"
    "PWNvbXBhcmVfcHJvbXB0KV0pLAogICAgICAgICAgICAgICAgdGltZW91dD02MAogICAgICAgICAg"
    "ICApCiAgICAgICAgICAgIGZpbmFsX3N1bW1hcnkgPSBzdW1tYXJ5LmNvbnRlbnQKICAgICAgICBl"
    "eGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAgICAgICAgICAgIGZpbmFsX3N1bW1hcnkgPSAiXG4tLS1c"
    "biIuam9pbihbZiJb7YOte3JbJ3RhYiddfV0ge3JbJ3Jlc3VsdCddWzo1MDBdfSIgZm9yIHIgaW4g"
    "dGFiX3Jlc3VsdHNdKQoKICAgICMg66mU66qo66asIOyXheuNsOydtO2KuAogICAgX3VwZGF0ZV9t"
    "ZW1vcnlfZnJvbV90YXNrKGJvZHkudGFzaywgZmluYWxfc3VtbWFyeVs6NTAwXSkKICAgIGF1ZGl0"
    "X2xvZ2dlci5pbmZvKGYiTVVMVElUQUJfT0t8dGFicz17bGVuKHRhYl9yZXN1bHRzKX0iKQoKICAg"
    "IHJldHVybiB7CiAgICAgICAgInN1Y2Nlc3MiOiBUcnVlLAogICAgICAgICJzdW1tYXJ5IjogZmlu"
    "YWxfc3VtbWFyeSwKICAgICAgICAidGFicyI6IHRhYl9yZXN1bHRzLAogICAgICAgICJ0YWJfY291"
    "bnQiOiBsZW4odGFiX3Jlc3VsdHMpLAogICAgICAgICJ0aW1lc3RhbXAiOiBkYXRldGltZS5ub3co"
    "KS5pc29mb3JtYXQoKQogICAgfQoKIyBNdWx0aS1BZ2VudCDsl5Trk5ztj6zsnbjtirgKQGFwcC5w"
    "b3N0KCIvYnJvd3NlL211bHRpIikKQGxpbWl0ZXIubGltaXQoIjUvbWludXRlIikKYXN5bmMgZGVm"
    "IGJyb3dzZV9tdWx0aShyZXF1ZXN0OiBSZXF1ZXN0LCBib2R5OiBCcm93c2VSZXF1ZXN0LAogICAg"
    "ICAgICAgICAgICAgICAgICAgIF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkpOgogICAgdHJ5Ogog"
    "ICAgICAgIGZyb20gbXVsdGlfYWdlbnQuZ3JhcGggaW1wb3J0IGJ1aWxkX2dyYXBoCiAgICBleGNl"
    "cHQgSW1wb3J0RXJyb3I6CiAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbig1MDEsICJNdWx0aS1B"
    "Z2VudCBub3QgYXZhaWxhYmxlIChHUk9RX0FQSV9LRVkgcmVxdWlyZWQpIikKCiAgICBhdWRpdF9s"
    "b2dnZXIuaW5mbyhmIk1VTFRJfHtyZXF1ZXN0LmNsaWVudC5ob3N0fXx7Ym9keS50YXNrWzoxMDBd"
    "fSIpCgogICAgYXN5bmMgd2l0aCB0YXNrX3Nsb3QoKToKICAgICAgICB0cnk6CiAgICAgICAgICAg"
    "IGdyYXBoID0gYnVpbGRfZ3JhcGgoKQogICAgICAgICAgICBzdGF0ZSA9IHsib3JpZ2luYWxfdGFz"
    "ayI6IGJvZHkudGFzaywgIm1lc3NhZ2VzIjogW10sCiAgICAgICAgICAgICAgICAgICAgICJyZXNl"
    "YXJjaF9yZXN1bHRzIjogW10sICJicm93c2VyX3Jlc3VsdHMiOiBbXSwKICAgICAgICAgICAgICAg"
    "ICAgICAgIml0ZXJhdGlvbiI6IDAsICJyb3V0ZV9oaXN0b3J5IjogW10sICJuZXh0IjogInN1cGVy"
    "dmlzb3IifQoKICAgICAgICAgICAgIyBbQU5USS1MT09QXSBNdWx0aS1BZ2VudCDsoITssrQg7YOA"
    "7J6E7JWE7JuDCiAgICAgICAgICAgIGZpbmFsID0gYXdhaXQgYXN5bmNpby53YWl0X2ZvcigKICAg"
    "ICAgICAgICAgICAgIGdyYXBoLmFpbnZva2Uoc3RhdGUpLAogICAgICAgICAgICAgICAgdGltZW91"
    "dD1NVUxUSV9USU1FT1VUCiAgICAgICAgICAgICkKCiAgICAgICAgICAgIG1zZ3MgPSBmaW5hbC5n"
    "ZXQoIm1lc3NhZ2VzIiwgW10pCiAgICAgICAgICAgIGxhc3QgPSBtc2dzWy0xXS5jb250ZW50IGlm"
    "IG1zZ3MgZWxzZSAibm8gcmVzdWx0IgogICAgICAgICAgICB0b2tlbl9pbmZvID0ge30KICAgICAg"
    "ICAgICAgaWYgInRva2VuX3RyYWNrZXIiIGluIGZpbmFsIGFuZCBmaW5hbFsidG9rZW5fdHJhY2tl"
    "ciJdOgogICAgICAgICAgICAgICAgdG9rZW5faW5mbyA9IGZpbmFsWyJ0b2tlbl90cmFja2VyIl0u"
    "c3VtbWFyeQoKICAgICAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJNVUxUSV9PS3x0b2tlbnM9"
    "e3Rva2VuX2luZm8uZ2V0KCd0b3RhbF90b2tlbnMnLDApfSIpCiAgICAgICAgICAgIHJldHVybiB7"
    "InN1Y2Nlc3MiOiBUcnVlLCAicmVzdWx0IjogbGFzdCwKICAgICAgICAgICAgICAgICAgICAidG9r"
    "ZW5fdXNhZ2UiOiB0b2tlbl9pbmZvLAogICAgICAgICAgICAgICAgICAgICJ0aW1lc3RhbXAiOiBk"
    "YXRldGltZS5ub3coKS5pc29mb3JtYXQoKX0KCiAgICAgICAgZXhjZXB0IGFzeW5jaW8uVGltZW91"
    "dEVycm9yOgogICAgICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIk1VTFRJX1RJTUVPVVR8e01V"
    "TFRJX1RJTUVPVVR9cyIpCiAgICAgICAgICAgIHJldHVybiB7InN1Y2Nlc3MiOiBGYWxzZSwKICAg"
    "ICAgICAgICAgICAgICAgICAiZXJyb3IiOiBmIk11bHRpLUFnZW50IHRpbWVkIG91dCBhZnRlciB7"
    "TVVMVElfVElNRU9VVH1zIiwKICAgICAgICAgICAgICAgICAgICAidGltZXN0YW1wIjogZGF0ZXRp"
    "bWUubm93KCkuaXNvZm9ybWF0KCl9CiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAg"
    "ICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIk1VTFRJX0ZBSUx8e2V9IikKICAgICAgICAgICAg"
    "cmV0dXJuIHsic3VjY2VzcyI6IEZhbHNlLCAiZXJyb3IiOiBzdHIoZSksCiAgICAgICAgICAgICAg"
    "ICAgICAgInRpbWVzdGFtcCI6IGRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpfQoKCgojIOKUgOKU"
    "gCDrqZTrqqjrpqwg7JeU65Oc7Y+s7J247Yq4IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApAYXBwLmdldCgi"
    "L21lbW9yeSIpCmFzeW5jIGRlZiBnZXRfbWVtb3J5KF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkp"
    "OgogICAgcmV0dXJuIF9sb2FkX21lbW9yeSgpCgpAYXBwLnBvc3QoIi9tZW1vcnkiKQphc3luYyBk"
    "ZWYgdXBkYXRlX21lbW9yeShyZXF1ZXN0OiBSZXF1ZXN0LCBfPURlcGVuZHModmVyaWZ5X2FwaV9r"
    "ZXkpKToKICAgIGJvZHkgPSBhd2FpdCByZXF1ZXN0Lmpzb24oKQogICAgbWVtID0gX2xvYWRfbWVt"
    "b3J5KCkKICAgIGlmICJsb2NhdGlvbiIgaW4gYm9keTogbWVtWyJsb2NhdGlvbiJdID0gc3RyKGJv"
    "ZHlbImxvY2F0aW9uIl0pWzo1MF0KICAgIGlmICJpbnRlcmVzdHMiIGluIGJvZHk6IG1lbVsiaW50"
    "ZXJlc3RzIl0gPSBbc3RyKGkpWzozMF0gZm9yIGkgaW4gYm9keVsiaW50ZXJlc3RzIl1bOjIwXV0K"
    "ICAgIGlmICJwcmVmZXJlbmNlcyIgaW4gYm9keTogbWVtWyJwcmVmZXJlbmNlcyJdLnVwZGF0ZShi"
    "b2R5WyJwcmVmZXJlbmNlcyJdKQogICAgaWYgImZhY3RzIiBpbiBib2R5OiBtZW1bImZhY3RzIl0g"
    "PSAobWVtLmdldCgiZmFjdHMiLFtdKSArIFtzdHIoZilbOjIwMF0gZm9yIGYgaW4gYm9keVsiZmFj"
    "dHMiXV0pWy0zMDpdCiAgICBfc2F2ZV9tZW1vcnkobWVtKQogICAgYXVkaXRfbG9nZ2VyLmluZm8o"
    "ZiJNRU1PUllfVVBEQVRFfHtsaXN0KGJvZHkua2V5cygpKX0iKQogICAgcmV0dXJuIHsic3VjY2Vz"
    "cyI6IFRydWUsICJtZW1vcnkiOiBtZW19CgpAYXBwLmRlbGV0ZSgiL21lbW9yeSIpCmFzeW5jIGRl"
    "ZiBjbGVhcl9tZW1vcnkoXz1EZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAgICBfc2F2ZV9tZW1v"
    "cnkoeyJsb2NhdGlvbiI6IiIsImludGVyZXN0cyI6W10sInByZWZlcmVuY2VzIjp7fSwiZmFjdHMi"
    "OltdLCJwYXN0X3F1ZXJpZXMiOltdfSkKICAgIHJldHVybiB7InN1Y2Nlc3MiOiBUcnVlLCAibWVz"
    "c2FnZSI6ICJNZW1vcnkgY2xlYXJlZCJ9CgojIOKUgOKUgCDtjIzsnbwg7KCR6re8IOyXlOuTnO2P"
    "rOyduO2KuCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIAKQGFwcC5nZXQoIi9maWxlcyIpCmFzeW5jIGRlZiBsaXN0X2ZpbGVz"
    "KF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkpOgogICAgaWYgbm90IFVTRVJfRklMRVNfRElSLmV4"
    "aXN0cygpOgogICAgICAgIHJldHVybiB7ImZpbGVzIjogW10sICJtZXNzYWdlIjogIk5vIHVzZXJf"
    "ZmlsZXMgZGlyZWN0b3J5In0KICAgIGZpbGVzID0gW10KICAgIGZvciBmIGluIHNvcnRlZChVU0VS"
    "X0ZJTEVTX0RJUi5pdGVyZGlyKCkpOgogICAgICAgIGlmIGYuaXNfZmlsZSgpIGFuZCBmLnN1ZmZp"
    "eC5sb3dlcigpIGluIEFMTE9XRURfRklMRV9FWFQ6CiAgICAgICAgICAgIGZpbGVzLmFwcGVuZCh7"
    "Im5hbWUiOiBmLm5hbWUsICJzaXplIjogZi5zdGF0KCkuc3Rfc2l6ZSwKICAgICAgICAgICAgICAg"
    "ICAgICAgICAgICAibW9kaWZpZWQiOiBkYXRldGltZS5mcm9tdGltZXN0YW1wKGYuc3RhdCgpLnN0"
    "X210aW1lKS5pc29mb3JtYXQoKX0pCiAgICByZXR1cm4geyJmaWxlcyI6IGZpbGVzLCAiY291bnQi"
    "OiBsZW4oZmlsZXMpfQoKQGFwcC5nZXQoIi9maWxlcy97ZmlsZW5hbWV9IikKYXN5bmMgZGVmIHJl"
    "YWRfZmlsZShmaWxlbmFtZTogc3RyLCBfPURlcGVuZHModmVyaWZ5X2FwaV9rZXkpKToKICAgIHRy"
    "eToKICAgICAgICBwYXRoID0gX3NhZmVfcGF0aChmaWxlbmFtZSkKICAgICAgICBpZiBub3QgcGF0"
    "aC5leGlzdHMoKToKICAgICAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbig0MDQsIGYiRmlsZSBu"
    "b3QgZm91bmQ6IHtmaWxlbmFtZX0iKQogICAgICAgIGlmIHBhdGguc3VmZml4Lmxvd2VyKCkgaW4g"
    "KCIucGRmIiwgIi54bHN4IiwgIi54bHMiLCAiLmRvY3giKToKICAgICAgICAgICAgcmV0dXJuIHsi"
    "bmFtZSI6IGZpbGVuYW1lLCAidHlwZSI6IHBhdGguc3VmZml4LAogICAgICAgICAgICAgICAgICAg"
    "ICJtZXNzYWdlIjogIkJpbmFyeSBmaWxlIOKAlCB1c2UgL2Jyb3dzZSB0byBhc2sgQUkgdG8gYW5h"
    "bHl6ZSBpdCJ9CiAgICAgICAgdGV4dCA9IHBhdGgucmVhZF90ZXh0KCJ1dGYtOCIsIGVycm9ycz0i"
    "cmVwbGFjZSIpWzo1MDAwMF0KICAgICAgICByZXR1cm4geyJuYW1lIjogZmlsZW5hbWUsICJjb250"
    "ZW50IjogdGV4dCwgInNpemUiOiBsZW4odGV4dCl9CiAgICBleGNlcHQgVmFsdWVFcnJvciBhcyBl"
    "OgogICAgICAgIHJhaXNlIEhUVFBFeGNlcHRpb24oNDAwLCBzdHIoZSkpCgpAYXBwLnBvc3QoIi9m"
    "aWxlcy97ZmlsZW5hbWV9IikKQGxpbWl0ZXIubGltaXQoIjEwL21pbnV0ZSIpCmFzeW5jIGRlZiB3"
    "cml0ZV9maWxlKHJlcXVlc3Q6IFJlcXVlc3QsIGZpbGVuYW1lOiBzdHIsIF89RGVwZW5kcyh2ZXJp"
    "ZnlfYXBpX2tleSkpOgogICAgdHJ5OgogICAgICAgIHBhdGggPSBfc2FmZV9wYXRoKGZpbGVuYW1l"
    "KQogICAgICAgIGJvZHkgPSBhd2FpdCByZXF1ZXN0Lmpzb24oKQogICAgICAgIHRleHQgPSBzdHIo"
    "Ym9keS5nZXQoImNvbnRlbnQiLCAiIikpWzoxMDAwMDBdCiAgICAgICAgVVNFUl9GSUxFU19ESVIu"
    "bWtkaXIocGFyZW50cz1UcnVlLCBleGlzdF9vaz1UcnVlKQogICAgICAgIHBhdGgud3JpdGVfdGV4"
    "dCh0ZXh0LCAidXRmLTgiKQogICAgICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiRklMRV9XUklURXx7"
    "ZmlsZW5hbWV9fHtsZW4odGV4dCl9Ynl0ZXMiKQogICAgICAgIHJldHVybiB7InN1Y2Nlc3MiOiBU"
    "cnVlLCAibmFtZSI6IGZpbGVuYW1lLCAic2l6ZSI6IGxlbih0ZXh0KX0KICAgIGV4Y2VwdCBWYWx1"
    "ZUVycm9yIGFzIGU6CiAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbig0MDAsIHN0cihlKSkKCiMg"
    "W1NFQ1VSSVRZXSDsg4Htg5wg7ZmV7J247JqpICjqtIDrpqzsnpAg7KCE7JqpKQpAYXBwLmdldCgi"
    "L21ldHJpY3MiKQphc3luYyBkZWYgbWV0cmljcyhyZXF1ZXN0OiBSZXF1ZXN0LCBfPURlcGVuZHMo"
    "dmVyaWZ5X2FwaV9rZXkpKToKICAgIHJldHVybiB7CiAgICAgICAgImFjdGl2ZV90YXNrcyI6IF9h"
    "Y3RpdmVfdGFza3MsCiAgICAgICAgIm1heF9jb25jdXJyZW50IjogTUFYX0NPTkNVUlJFTlQsCiAg"
    "ICAgICAgIm1vZGVsIjogR1JPUV9NT0RFTCwKICAgICAgICAidGltZW91dHMiOiB7CiAgICAgICAg"
    "ICAgICJ0YXNrIjogVEFTS19USU1FT1VULAogICAgICAgICAgICAibXVsdGkiOiBNVUxUSV9USU1F"
    "T1VULAogICAgICAgICAgICAic3RlcCI6IFNURVBfVElNRU9VVAogICAgICAgIH0KICAgIH0KCiMg"
    "4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ"
    "4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ"
    "4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ"
    "4pWQ4pWQ4pWQCiMgW3Y3XSDqsoDsg4kg7JeU65Oc7Y+s7J247Yq4IOKAlCDrhKTsnbTrsoQg6rKA"
    "7IOJIEFQSSArIFRhdmlseSAo67iM65287Jqw7KeVIOuMgOyytCkKIyDquLDsobQg67O07JWIIOqz"
    "hOy4tSDsg4Hsho06IHZlcmlmeV9hcGlfa2V5LCDqsJDsgqwg66Gc6re4LCBmaWx0ZXJfcmVzcG9u"
    "c2UsIHJhdGUgbGltaXQuCiMgQVBJIO2CpOuKlCDshJzrsoQgLmVudiDsl5Drp4wg7KG07J6s7ZWY"
    "66mwIOydkeuLteyXkCDrhbjstpzrkJjsp4Ag7JWK64qU64ukLgojIOKVkOKVkOKVkOKVkOKVkOKV"
    "kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV"
    "kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKV"
    "kOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkOKVkApfSEFOR1VM"
    "X1JFID0gX3JlLmNvbXBpbGUociJbXHVhYzAwLVx1ZDdhM10iKQoKZGVmIF9pc19rb3JlYW5fcXVl"
    "cnkocSk6CiAgICByZXR1cm4gYm9vbChxIGFuZCBfSEFOR1VMX1JFLnNlYXJjaChxKSkKCmRlZiBf"
    "c2NhY2hlX2dldChuYW1lLCBxKToKICAgIGlmIFNFQVJDSF9DQUNIRV9UVEwgPD0gMDoKICAgICAg"
    "ICByZXR1cm4gTm9uZQogICAgZSA9IF9zZWFyY2hfY2FjaGUuZ2V0KChuYW1lLCBxKSkKICAgIGlm"
    "IGUgYW5kICh0aW1lLnRpbWUoKSAtIGVbMV0pIDwgU0VBUkNIX0NBQ0hFX1RUTDoKICAgICAgICBy"
    "ZXR1cm4gZVswXQogICAgcmV0dXJuIE5vbmUKCmRlZiBfc2NhY2hlX3NldChuYW1lLCBxLCBkYXRh"
    "KToKICAgIGlmIFNFQVJDSF9DQUNIRV9UVEwgPiAwOgogICAgICAgIF9zZWFyY2hfY2FjaGVbKG5h"
    "bWUsIHEpXSA9IChkYXRhLCB0aW1lLnRpbWUoKSkKICAgICAgICBpZiBsZW4oX3NlYXJjaF9jYWNo"
    "ZSkgPiAyMDA6CiAgICAgICAgICAgIG9sZGVzdCA9IG1pbihfc2VhcmNoX2NhY2hlLCBrZXk9bGFt"
    "YmRhIGs6IF9zZWFyY2hfY2FjaGVba11bMV0pCiAgICAgICAgICAgIGRlbCBfc2VhcmNoX2NhY2hl"
    "W29sZGVzdF0KCmRlZiBfc3RyaXBfdGFncyhzKToKICAgIHMgPSBfcmUuc3ViKHIiPFtePl0rPiIs"
    "ICIiLCBzIG9yICIiKQogICAgcmV0dXJuIChzLnJlcGxhY2UoIiZxdW90OyIsICciJykucmVwbGFj"
    "ZSgiJmFtcDsiLCAiJiIpCiAgICAgICAgICAgICAucmVwbGFjZSgiJmx0OyIsICI8IikucmVwbGFj"
    "ZSgiJmd0OyIsICI+IikucmVwbGFjZSgiJm5ic3A7IiwgIiAiKSkKCmFzeW5jIGRlZiBfbmF2ZXJf"
    "YXBpX3NlYXJjaChxdWVyeSwga2luZD0id2Via3IiLCBkaXNwbGF5PTUpOgogICAgaWYgbm90IChO"
    "QVZFUl9DTElFTlRfSUQgYW5kIE5BVkVSX0NMSUVOVF9TRUNSRVQpOgogICAgICAgIHJldHVybiB7"
    "Im9rIjogRmFsc2UsICJlcnJvciI6ICJOQVZFUiBrZXlzIG5vdCBjb25maWd1cmVkIiwgIml0ZW1z"
    "IjogW119CiAgICBjYWNoZWQgPSBfc2NhY2hlX2dldCgibmF2ZXI6IiArIGtpbmQsIHF1ZXJ5KQog"
    "ICAgaWYgY2FjaGVkIGlzIG5vdCBOb25lOgogICAgICAgIHJldHVybiBjYWNoZWQKICAgIGltcG9y"
    "dCBodHRweAogICAgZW5kcG9pbnQgPSB7CiAgICAgICAgIndlYmtyIjogImh0dHBzOi8vb3BlbmFw"
    "aS5uYXZlci5jb20vdjEvc2VhcmNoL3dlYmtyLmpzb24iLAogICAgICAgICJuZXdzIjogICJodHRw"
    "czovL29wZW5hcGkubmF2ZXIuY29tL3YxL3NlYXJjaC9uZXdzLmpzb24iLAogICAgICAgICJibG9n"
    "IjogICJodHRwczovL29wZW5hcGkubmF2ZXIuY29tL3YxL3NlYXJjaC9ibG9nLmpzb24iLAogICAg"
    "ICAgICJlbmN5YyI6ICJodHRwczovL29wZW5hcGkubmF2ZXIuY29tL3YxL3NlYXJjaC9lbmN5Yy5q"
    "c29uIiwKICAgICAgICAibG9jYWwiOiAiaHR0cHM6Ly9vcGVuYXBpLm5hdmVyLmNvbS92MS9zZWFy"
    "Y2gvbG9jYWwuanNvbiIsCiAgICB9LmdldChraW5kLCAiaHR0cHM6Ly9vcGVuYXBpLm5hdmVyLmNv"
    "bS92MS9zZWFyY2gvd2Via3IuanNvbiIpCiAgICBoZWFkZXJzID0geyJYLU5hdmVyLUNsaWVudC1J"
    "ZCI6IE5BVkVSX0NMSUVOVF9JRCwKICAgICAgICAgICAgICAgIlgtTmF2ZXItQ2xpZW50LVNlY3Jl"
    "dCI6IE5BVkVSX0NMSUVOVF9TRUNSRVR9CiAgICBwYXJhbXMgPSB7InF1ZXJ5IjogcXVlcnksICJk"
    "aXNwbGF5IjogbWF4KDEsIG1pbihkaXNwbGF5LCAxMCkpfQogICAgdHJ5OgogICAgICAgIGFzeW5j"
    "IHdpdGggaHR0cHguQXN5bmNDbGllbnQodGltZW91dD1TRUFSQ0hfVElNRU9VVCkgYXMgYzoKICAg"
    "ICAgICAgICAgciA9IGF3YWl0IGMuZ2V0KGVuZHBvaW50LCBoZWFkZXJzPWhlYWRlcnMsIHBhcmFt"
    "cz1wYXJhbXMpCiAgICAgICAgaWYgci5zdGF0dXNfY29kZSAhPSAyMDA6CiAgICAgICAgICAgIHJl"
    "dHVybiB7Im9rIjogRmFsc2UsICJlcnJvciI6ICJuYXZlciBodHRwICVzIiAlIHIuc3RhdHVzX2Nv"
    "ZGUsICJpdGVtcyI6IFtdfQogICAgICAgIGRhdGEgPSByLmpzb24oKQogICAgICAgIGl0ZW1zID0g"
    "W3sidGl0bGUiOiBfc3RyaXBfdGFncyhpdC5nZXQoInRpdGxlIiwgIiIpKSwKICAgICAgICAgICAg"
    "ICAgICAgInNuaXBwZXQiOiBfc3RyaXBfdGFncyhpdC5nZXQoImRlc2NyaXB0aW9uIiwgIiIpKSwK"
    "ICAgICAgICAgICAgICAgICAgInVybCI6IGl0LmdldCgibGluayIsICIiKX0gZm9yIGl0IGluIGRh"
    "dGEuZ2V0KCJpdGVtcyIsIFtdKV0KICAgICAgICBvdXQgPSB7Im9rIjogVHJ1ZSwgInNvdXJjZSI6"
    "ICJuYXZlcjoiICsga2luZCwgIml0ZW1zIjogaXRlbXN9CiAgICAgICAgX3NjYWNoZV9zZXQoIm5h"
    "dmVyOiIgKyBraW5kLCBxdWVyeSwgb3V0KQogICAgICAgIHJldHVybiBvdXQKICAgIGV4Y2VwdCBF"
    "eGNlcHRpb24gYXMgZToKICAgICAgICByZXR1cm4geyJvayI6IEZhbHNlLCAiZXJyb3IiOiAibmF2"
    "ZXI6ICVzIiAlIGUsICJpdGVtcyI6IFtdfQoKYXN5bmMgZGVmIF90YXZpbHlfc2VhcmNoKHF1ZXJ5"
    "LCBtYXhfcmVzdWx0cz01KToKICAgIGlmIG5vdCBUQVZJTFlfQVBJX0tFWToKICAgICAgICByZXR1"
    "cm4geyJvayI6IEZhbHNlLCAiZXJyb3IiOiAiVEFWSUxZIGtleSBub3QgY29uZmlndXJlZCIsICJp"
    "dGVtcyI6IFtdLCAiYW5zd2VyIjogIiJ9CiAgICBjYWNoZWQgPSBfc2NhY2hlX2dldCgidGF2aWx5"
    "IiwgcXVlcnkpCiAgICBpZiBjYWNoZWQgaXMgbm90IE5vbmU6CiAgICAgICAgcmV0dXJuIGNhY2hl"
    "ZAogICAgaW1wb3J0IGh0dHB4CiAgICB0cnk6CiAgICAgICAgYXN5bmMgd2l0aCBodHRweC5Bc3lu"
    "Y0NsaWVudCh0aW1lb3V0PVNFQVJDSF9USU1FT1VUKSBhcyBjOgogICAgICAgICAgICByID0gYXdh"
    "aXQgYy5wb3N0KCJodHRwczovL2FwaS50YXZpbHkuY29tL3NlYXJjaCIsIGpzb249ewogICAgICAg"
    "ICAgICAgICAgImFwaV9rZXkiOiBUQVZJTFlfQVBJX0tFWSwgInF1ZXJ5IjogcXVlcnksCiAgICAg"
    "ICAgICAgICAgICAibWF4X3Jlc3VsdHMiOiBtYXgoMSwgbWluKG1heF9yZXN1bHRzLCAxMCkpLAog"
    "ICAgICAgICAgICAgICAgImluY2x1ZGVfYW5zd2VyIjogVHJ1ZSwgInNlYXJjaF9kZXB0aCI6ICJi"
    "YXNpYyJ9KQogICAgICAgIGlmIHIuc3RhdHVzX2NvZGUgIT0gMjAwOgogICAgICAgICAgICByZXR1"
    "cm4geyJvayI6IEZhbHNlLCAiZXJyb3IiOiAidGF2aWx5IGh0dHAgJXMiICUgci5zdGF0dXNfY29k"
    "ZSwgIml0ZW1zIjogW10sICJhbnN3ZXIiOiAiIn0KICAgICAgICBkYXRhID0gci5qc29uKCkKICAg"
    "ICAgICBpdGVtcyA9IFt7InRpdGxlIjogaXQuZ2V0KCJ0aXRsZSIsICIiKSwgInNuaXBwZXQiOiBp"
    "dC5nZXQoImNvbnRlbnQiLCAiIiksCiAgICAgICAgICAgICAgICAgICJ1cmwiOiBpdC5nZXQoInVy"
    "bCIsICIiKX0gZm9yIGl0IGluIGRhdGEuZ2V0KCJyZXN1bHRzIiwgW10pXQogICAgICAgIG91dCA9"
    "IHsib2siOiBUcnVlLCAic291cmNlIjogInRhdmlseSIsICJhbnN3ZXIiOiBkYXRhLmdldCgiYW5z"
    "d2VyIiwgIiIpLCAiaXRlbXMiOiBpdGVtc30KICAgICAgICBfc2NhY2hlX3NldCgidGF2aWx5Iiwg"
    "cXVlcnksIG91dCkKICAgICAgICByZXR1cm4gb3V0CiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6"
    "CiAgICAgICAgcmV0dXJuIHsib2siOiBGYWxzZSwgImVycm9yIjogInRhdmlseTogJXMiICUgZSwg"
    "Iml0ZW1zIjogW10sICJhbnN3ZXIiOiAiIn0KCmRlZiBfZm9ybWF0X3NlYXJjaF9yZXN1bHRzKHJl"
    "cyk6CiAgICBpZiBub3QgcmVzLmdldCgib2siKToKICAgICAgICByZXR1cm4gIuqygOyDiSDsi6Tt"
    "jKg6ICVzIiAlIHJlcy5nZXQoImVycm9yIiwgIuyVjCDsiJgg7JeG64qUIOyYpOulmCIpCiAgICBs"
    "aW5lcyA9IFtdCiAgICBpZiByZXMuZ2V0KCJhbnN3ZXIiKToKICAgICAgICBsaW5lcy5hcHBlbmQo"
    "IuyalOyVvTogIiArIHJlc1siYW5zd2VyIl0pOyBsaW5lcy5hcHBlbmQoIiIpCiAgICBmb3IgaSwg"
    "aXQgaW4gZW51bWVyYXRlKHJlcy5nZXQoIml0ZW1zIiwgW10pLCAxKToKICAgICAgICB0ID0gKGl0"
    "LmdldCgidGl0bGUiKSBvciAiIikuc3RyaXAoKQogICAgICAgIHNuID0gKGl0LmdldCgic25pcHBl"
    "dCIpIG9yICIiKS5zdHJpcCgpCiAgICAgICAgdSA9IChpdC5nZXQoInVybCIpIG9yICIiKS5zdHJp"
    "cCgpCiAgICAgICAgYmxvY2sgPSAoIiVkLiAlcyIgJSAoaSwgdCkpIGlmIHQgZWxzZSAoIiVkLiIg"
    "JSBpKQogICAgICAgIGlmIHNuOgogICAgICAgICAgICBibG9jayArPSAiXG4gICAiICsgc24KICAg"
    "ICAgICBpZiB1OgogICAgICAgICAgICBibG9jayArPSAiXG4gICAiICsgdQogICAgICAgIGxpbmVz"
    "LmFwcGVuZChibG9jaykKICAgIHJldHVybiAiXG4iLmpvaW4obGluZXMpIGlmIGxpbmVzIGVsc2Ug"
    "IuqygOyDiSDqsrDqs7zqsIAg7JeG7Iq164uI64ukLiIKCmNsYXNzIFNlYXJjaFJlcXVlc3QoQmFz"
    "ZU1vZGVsKToKICAgIHF1ZXJ5OiBzdHIgPSBGaWVsZCguLi4sIG1pbl9sZW5ndGg9MSwgbWF4X2xl"
    "bmd0aD01MDApCiAgICBraW5kOiBzdHIgPSBGaWVsZChkZWZhdWx0PSJhdXRvIiwgbWF4X2xlbmd0"
    "aD0yMCkKICAgIGRpc3BsYXk6IGludCA9IEZpZWxkKGRlZmF1bHQ9NSwgZ2U9MSwgbGU9MTApCgpA"
    "YXBwLnBvc3QoIi9zZWFyY2giKQpAbGltaXRlci5saW1pdCgiMjAvbWludXRlIikKYXN5bmMgZGVm"
    "IHNlYXJjaChyZXF1ZXN0OiBSZXF1ZXN0LCBib2R5OiBTZWFyY2hSZXF1ZXN0LCBfPURlcGVuZHMo"
    "dmVyaWZ5X2FwaV9rZXkpKToKICAgICIiIuuEpOydtOuyhCDqsoDsg4kgQVBJICsgVGF2aWx5IO2V"
    "mOydtOu4jOumrOuTnC4g7ZWc6rWt7Ja04oaS64Sk7J2067KELCDqt7gg7Jm44oaSVGF2aWx5LiIi"
    "IgogICAgcSA9IGJvZHkucXVlcnkuc3RyaXAoKQogICAgaWYgbm90IHE6CiAgICAgICAgcmFpc2Ug"
    "SFRUUEV4Y2VwdGlvbig0MDAsICJlbXB0eSBxdWVyeSIpCiAgICBjaXAgPSByZXF1ZXN0LmNsaWVu"
    "dC5ob3N0IGlmIHJlcXVlc3QuY2xpZW50IGVsc2UgIj8iCiAgICBhdWRpdF9sb2dnZXIuaW5mbygi"
    "U0VBUkNIfCVzfGtpbmQ9JXN8JXMiICUgKGNpcCwgYm9keS5raW5kLCBxWzo4MF0pKQogICAga2lu"
    "ZCA9IGJvZHkua2luZC5sb3dlcigpCiAgICBpZiBraW5kIGluICgid2Via3IiLCAibmV3cyIsICJi"
    "bG9nIiwgImVuY3ljIiwgImxvY2FsIik6CiAgICAgICAgcmVzID0gYXdhaXQgX25hdmVyX2FwaV9z"
    "ZWFyY2gocSwga2luZCwgYm9keS5kaXNwbGF5KTsgcm91dGVkID0gIm5hdmVyOiIgKyBraW5kCiAg"
    "ICBlbGlmIGtpbmQgPT0gIndlYiI6CiAgICAgICAgcmVzID0gYXdhaXQgX3RhdmlseV9zZWFyY2go"
    "cSwgYm9keS5kaXNwbGF5KTsgcm91dGVkID0gInRhdmlseSIKICAgIGVsc2U6CiAgICAgICAgaWYg"
    "X2lzX2tvcmVhbl9xdWVyeShxKToKICAgICAgICAgICAgcmVzID0gYXdhaXQgX25hdmVyX2FwaV9z"
    "ZWFyY2gocSwgIndlYmtyIiwgYm9keS5kaXNwbGF5KTsgcm91dGVkID0gIm5hdmVyOndlYmtyIgog"
    "ICAgICAgICAgICBpZiBub3QgcmVzLmdldCgib2siKSBvciBub3QgcmVzLmdldCgiaXRlbXMiKToK"
    "ICAgICAgICAgICAgICAgIHR2ID0gYXdhaXQgX3RhdmlseV9zZWFyY2gocSwgYm9keS5kaXNwbGF5"
    "KQogICAgICAgICAgICAgICAgaWYgdHYuZ2V0KCJvayIpIGFuZCB0di5nZXQoIml0ZW1zIik6CiAg"
    "ICAgICAgICAgICAgICAgICAgcmVzLCByb3V0ZWQgPSB0diwgInRhdmlseShmYWxsYmFjaykiCiAg"
    "ICAgICAgZWxzZToKICAgICAgICAgICAgcmVzID0gYXdhaXQgX3RhdmlseV9zZWFyY2gocSwgYm9k"
    "eS5kaXNwbGF5KTsgcm91dGVkID0gInRhdmlseSIKICAgICAgICAgICAgaWYgbm90IHJlcy5nZXQo"
    "Im9rIikgb3Igbm90IHJlcy5nZXQoIml0ZW1zIik6CiAgICAgICAgICAgICAgICBudiA9IGF3YWl0"
    "IF9uYXZlcl9hcGlfc2VhcmNoKHEsICJ3ZWJrciIsIGJvZHkuZGlzcGxheSkKICAgICAgICAgICAg"
    "ICAgIGlmIG52LmdldCgib2siKSBhbmQgbnYuZ2V0KCJpdGVtcyIpOgogICAgICAgICAgICAgICAg"
    "ICAgIHJlcywgcm91dGVkID0gbnYsICJuYXZlcjp3ZWJrcihmYWxsYmFjaykiCiAgICB0ZXh0ID0g"
    "X2Zvcm1hdF9zZWFyY2hfcmVzdWx0cyhyZXMpCiAgICB0cnk6CiAgICAgICAgdGV4dCA9IGZpbHRl"
    "cl9yZXNwb25zZSh0ZXh0KQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICBwYXNzCiAgICBv"
    "ayA9IGJvb2wocmVzLmdldCgib2siKSBhbmQgcmVzLmdldCgiaXRlbXMiKSkKICAgIGF1ZGl0X2xv"
    "Z2dlci5pbmZvKCJTRUFSQ0hfJXN8cm91dGVkPSVzfGl0ZW1zPSVkIiAlCiAgICAgICAgICAgICAg"
    "ICAgICAgICAoIk9LIiBpZiBvayBlbHNlICJFTVBUWSIsIHJvdXRlZCwgbGVuKHJlcy5nZXQoIml0"
    "ZW1zIiwgW10pKSkpCiAgICByZXR1cm4geyJzdWNjZXNzIjogb2ssICJyb3V0ZWQiOiByb3V0ZWQs"
    "ICJxdWVyeSI6IHEsCiAgICAgICAgICAgICJhbnN3ZXIiOiByZXMuZ2V0KCJhbnN3ZXIiLCAiIiks"
    "ICJyZXN1bHRzIjogcmVzLmdldCgiaXRlbXMiLCBbXSksCiAgICAgICAgICAgICJzdW1tYXJ5X3Bs"
    "YWluIjogdGV4dCwgInN1bW1hcnkiOiB0ZXh0LAogICAgICAgICAgICAidGltZXN0YW1wIjogZGF0"
    "ZXRpbWUubm93KCkuaXNvZm9ybWF0KCl9CgoKaWYgX19uYW1lX18gPT0gIl9fbWFpbl9fIjoKICAg"
    "IGltcG9ydCB1dmljb3JuCiAgICB1dmljb3JuLnJ1bihhcHAsIGhvc3Q9IjAuMC4wLjAiLCBwb3J0"
    "PTgwMDEsCiAgICAgICAgICAgICAgICBzZXJ2ZXJfaGVhZGVyPUZhbHNlLCAgIyBbU0VDVVJJVFld"
    "IOyEnOuyhCDtl6TrjZQg7Iio6rmACiAgICAgICAgICAgICAgICBhY2Nlc3NfbG9nPVRydWUpCg=="
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
    if not auth or not auth.startswith("Bearer "):
        audit_logger.info(f"AUTH_MISSING|{request.client.host}|{request.url.path}")
        raise HTTPException(status_code=401, detail="Authorization required")
    token = auth.replace("Bearer ", "").strip()
    if not hmac.compare_digest(token.encode(), key.encode()):
        audit_logger.info(f"AUTH_FAIL|{request.client.host}|{request.url.path}")
        raise HTTPException(status_code=403, detail="Invalid API key")'''

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
    if not auth or not auth.startswith("Bearer "):
        _ip_fail(ip)
        audit_logger.info(f"AUTH_MISSING|{ip}|{request.url.path}")
        raise HTTPException(status_code=401, detail="Authorization required")
    token = auth.replace("Bearer ", "").strip()
    if not hmac.compare_digest(token.encode(), key.encode()):
        _ip_fail(ip)
        audit_logger.info(f"AUTH_FAIL|{ip}|{request.url.path}")
        raise HTTPException(status_code=403, detail="Invalid API key")
    _ip_ok(ip)  # 성공 시 카운터 초기화'''

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

def verify_request_signature(request: Request):
    """HMAC-SHA256 서명 + 타임스탬프로 Replay Attack 및 요청 위조 방지"""
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
    # HMAC-SHA256 검증
    key  = _load_api_key().encode()
    body = f"{ts}:{request.method}:{request.url.path}".encode()
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
OLD_SANITIZE_END = '''    for p in injection_patterns:
        if _re.search(p, task, _re.IGNORECASE):
            audit_logger.info(f"INJECTION_ATTEMPT|{p}|{task[:100]}")
            task = _re.sub(p, "[BLOCKED]", task, flags=_re.IGNORECASE)
    return task[:2000]'''

NEW_SANITIZE_END = '''    for p in injection_patterns:
        if _re.search(p, task, _re.IGNORECASE):
            audit_logger.info(f"INJECTION_ATTEMPT|{p}|{task[:100]}")
            task = _re.sub(p, "[BLOCKED]", task, flags=_re.IGNORECASE)
    return task[:2000]

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
        resolved = str(_pathlib.Path(DATA_DIR / filename).resolve())
        if not resolved.startswith(str(_pathlib.Path(DATA_DIR).resolve())):
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
_ah.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
audit_logger.addHandler(_ah)
audit_logger.setLevel(logging.INFO)'''

NEW_AUDIT_SETUP = '''audit_logger = logging.getLogger("audit")
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
    mem = load_memory()
    mem.update(body)
    save_memory(mem)
    audit_logger.info(f"MEMORY_UPDATE|{list(body.keys())}")'''
NEW_MEM_BODY = '''    body = await request.json()
    body = validate_memory_update(body)  # [SECURITY] 스키마 검증
    mem = load_memory()
    mem.update(body)
    save_memory(mem)
    _audit("MEMORY_UPDATE", detail=str(list(body.keys())))'''
if OLD_MEM_BODY in code:
    code = code.replace(OLD_MEM_BODY, NEW_MEM_BODY)
    print("  ✅ 패치 ⑤-b: update_memory에 스키마 검증 연결")

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
            from browser_use.browser.browser import Browser, BrowserConfig
            proxy_cfg = BrowserConfig(headless=True,
                proxy={"server": BROWSER_PROXY} if BROWSER_PROXY else None)
            task_str = (f"URL: {body.url}\n" if body.url else "") + body.task
            async def _run():
                s = None
                try:
                    s = Browser(config=proxy_cfg)
                    ag = Agent(task=task_str, llm=llm, browser=s, use_vision=False, max_actions_per_step=5)
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
        from browser_use.browser.browser import Browser, BrowserConfig
        proxy_cfg = BrowserConfig(headless=True, proxy={"server": BROWSER_PROXY} if BROWSER_PROXY else None)
        task_str = (f"URL: {item.url}\n" if item.url else "") + item.task
        try:
            s  = Browser(config=proxy_cfg)
            ag = Agent(task=task_str, llm=llm, browser=s, use_vision=False, max_actions_per_step=5)
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
def _vsn(n): return bool(re.match(r'^[a-zA-Z0-9_-]{1,32}$', n))

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
    from browser_use.browser.browser import Browser, BrowserConfig
    proxy_cfg = BrowserConfig(headless=True, proxy={"server":BROWSER_PROXY} if BROWSER_PROXY else None)
    task = f"URL: {mon['url']}\n{mon['keyword']} 현재값을 알려줘."
    if mon.get("target_value"): task += f" 목표: '{mon['target_value']}'과 비교."
    try:
        s = Browser(config=proxy_cfg)
        ag = Agent(task=task, llm=llm, browser=s, use_vision=False, max_actions_per_step=5)
        r  = await asyncio.wait_for(ag.run(max_steps=8), timeout=60)
        await asyncio.wait_for(s.close(), timeout=5)
        cv = filter_response(r.final_result() or "")
    except Exception as e: cv = f"오류: {e}"
    mon.update({"last_checked":time.strftime("%Y-%m-%dT%H:%M:%S"),"last_value":cv[:200]})
    triggered = bool(mon.get("target_value") and mon["target_value"] in cv)
    if triggered: mon["triggered"] = True
    _save_monitors(); _audit("MONITOR_CHECK", detail=f"{mid}|triggered={triggered}")
    return {"id":mid,"current_value":cv[:400],"triggered":triggered,"checked_at":mon["last_checked"]}

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
                    from browser_use.browser.browser import Browser, BrowserConfig
                    proxy_cfg = BrowserConfig(headless=True, proxy={"server":BROWSER_PROXY} if BROWSER_PROXY else None)
                    s  = Browser(config=proxy_cfg)
                    ag = Agent(task=f"URL: {mon['url']}\n{mon['keyword']} 현재값을 알려줘.",
                               llm=llm, browser=s, use_vision=False, max_actions_per_step=5)
                    r  = await asyncio.wait_for(ag.run(max_steps=6), timeout=60)
                    await asyncio.wait_for(s.close(), timeout=5)
                    cv = filter_response(r.final_result() or "")
                    mon.update({"last_checked":time.strftime("%Y-%m-%dT%H:%M:%S"),"last_value":cv[:200]})
                    if mon.get("target_value") and mon["target_value"] in cv:
                        mon["triggered"] = True; logger.info(f"🔔 모니터 트리거: {mid}")
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
        return C(model_name=os.environ.get("GROQ_MODEL","llama-3.3-70b-versatile"),
                 api_key=key, temperature=0, max_retries=3)

async def _search_via_api(task, display=5):
    """[v7] 같은 컨테이너의 /search 엔드포인트(네이버 API + Tavily) 호출.
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
    "ICAgICAgICAgcmV0dXJuIGYi7Jik66WYOiB7ZX0iCgogICAgYXN5bmMgZGVmIF9hcGlfc2VhcmNo"
    "KHNlbGYsIHF1ZXJ5LCBraW5kPSJhdXRvIiwgZGlzcGxheT01LCBfX2V2ZW50X2VtaXR0ZXJfXz1O"
    "b25lKToKICAgICAgICAiIiJicm93c2VyLWFnZW50IOydmCAvc2VhcmNoIOyXlOuTnO2PrOyduO2K"
    "uCDtmLjstpwgKOuEpOydtOuyhCBBUEkgKyBUYXZpbHkpLgogICAgICAgIOu4jOudvOyasOyggCDq"
    "uIHquLAg64yA7IugIOqzteyLnSDqsoDsg4kgQVBJIOulvCDsgqzsmqntlZzri6QuIiIiCiAgICAg"
    "ICAgY2FjaGVkID0gc2VsZi5fZ2V0X2NhY2hlKCJzZWFyY2g6JXM6JXMiICUgKGtpbmQsIHF1ZXJ5"
    "KSkKICAgICAgICBpZiBjYWNoZWQ6IHJldHVybiBjYWNoZWQKICAgICAgICBhc3luYyBkZWYgZW1p"
    "dChtc2csIGRvbmU9RmFsc2UpOgogICAgICAgICAgICBpZiBfX2V2ZW50X2VtaXR0ZXJfXzogYXdh"
    "aXQgX19ldmVudF9lbWl0dGVyX18oeyJ0eXBlIjoic3RhdHVzIiwiZGF0YSI6eyJkZXNjcmlwdGlv"
    "biI6bXNnLCJkb25lIjpkb25lfX0pCiAgICAgICAgYXdhaXQgZW1pdCgi6rKA7IOJIOykkS4uLiIp"
    "CiAgICAgICAgdHJ5OgogICAgICAgICAgICByZXN1bHQgPSBhd2FpdCBzZWxmLl9wb3N0KCIvc2Vh"
    "cmNoIiwgeyJxdWVyeSI6IHF1ZXJ5LCAia2luZCI6IGtpbmQsICJkaXNwbGF5IjogZGlzcGxheX0p"
    "CiAgICAgICAgICAgIHRleHQgPSByZXN1bHQuZ2V0KCJzdW1tYXJ5X3BsYWluIikgb3IgcmVzdWx0"
    "LmdldCgic3VtbWFyeSIsICIiKQogICAgICAgICAgICBhd2FpdCBlbWl0KCLsmYTro4whIiwgZG9u"
    "ZT1UcnVlKQogICAgICAgICAgICBpZiB0ZXh0OiBzZWxmLl9zZXRfY2FjaGUoInNlYXJjaDolczol"
    "cyIgJSAoa2luZCwgcXVlcnkpLCB0ZXh0KQogICAgICAgICAgICByZXR1cm4gdGV4dCBvciAi6rKA"
    "7IOJIOqysOqzvOqwgCDsl4bsirXri4jri6QuIgogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMg"
    "ZToKICAgICAgICAgICAgYXdhaXQgZW1pdCgi7Jik66WYIiwgZG9uZT1UcnVlKQogICAgICAgICAg"
    "ICByZXR1cm4gIuqygOyDiSDsmKTrpZg6ICVzIiAlIGUKCiAgICBhc3luYyBkZWYgX25hdmVyX3Nl"
    "YXJjaChzZWxmLCBxdWVyeV9rciwgaW5zdHJ1Y3Rpb24sIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUp"
    "OgogICAgICAgICMgW3Y3XSDruIzrnbzsmrDsoIAg6riB6riwIOKGkiAvc2VhcmNoIOyXlOuTnO2P"
    "rOyduO2KuCjrhKTsnbTrsoQgQVBJKS4gaW5zdHJ1Y3Rpb24g7J2ACiAgICAgICAgIyBBUEkg6rKA"
    "7IOJ7JeQ7ISc64qUIOu2iO2VhOyalO2VmOuvgOuhnCDrrLTsi5ztlZjqs6AgcXVlcnkg66eMIOyC"
    "rOyaqe2VnOuLpC4KICAgICAgICByZXR1cm4gYXdhaXQgc2VsZi5fYXBpX3NlYXJjaChxdWVyeV9r"
    "ciwga2luZD0iYXV0byIsIF9fZXZlbnRfZW1pdHRlcl9fPV9fZXZlbnRfZW1pdHRlcl9fKQoKICAg"
    "IGRlZiBfdHJhbnNsYXRlX2tleXdvcmQoc2VsZiwga2V5d29yZCwga2V5d29yZF9tYXApOgogICAg"
    "ICAgIGt3ID0ga2V5d29yZC5sb3dlcigpLnN0cmlwKCkKICAgICAgICBpZiBrdyBpbiBrZXl3b3Jk"
    "X21hcDogcmV0dXJuIGtleXdvcmRfbWFwW2t3XQogICAgICAgIGZvciBlbmcsIGtvciBpbiBzb3J0"
    "ZWQoa2V5d29yZF9tYXAuaXRlbXMoKSwga2V5PWxhbWJkYSB4OiAtbGVuKHhbMF0pKToKICAgICAg"
    "ICAgICAgaWYgZW5nIGluIGt3OiByZXR1cm4ga3cucmVwbGFjZShlbmcsIGtvcikKICAgICAgICBy"
    "ZXR1cm4ga2V5d29yZAoKICAgIGFzeW5jIGRlZiBzZWFyY2hfbmF2ZXIoc2VsZiwga2V5d29yZCwg"
    "X19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiU2VhcmNoIE5hdmVyIGZvciByZWFs"
    "LXRpbWUgaW5mb3JtYXRpb24uCiAgICAgICAgOnBhcmFtIGtleXdvcmQ6IFNlYXJjaCBrZXl3b3Jk"
    "CiAgICAgICAgIiIiCiAgICAgICAgaWYgbm90IGtleXdvcmQuc3RyaXAoKTogcmV0dXJuICLqsoDs"
    "g4nslrTrpbwg7J6F66Cl7ZWY7IS47JqULiIKICAgICAgICBrbSA9IHsid2VhdGhlciI6IuuCoOyU"
    "qCIsIm5ld3MiOiLribTsiqQiLCJzdG9jayI6IuyjvOqwgCIsImV4Y2hhbmdlIHJhdGUiOiLtmZjs"
    "nKgiLCJwcmljZSI6IuqwgOqyqSIsCiAgICAgICAgICAgICAgImJpdGNvaW4iOiLruYTtirjsvZTs"
    "nbgiLCJzb2NjZXIiOiLstpXqtawiLCJiYXNlYmFsbCI6IuyVvOq1rCIsIm1vdmllIjoi7JiB7ZmU"
    "IiwidHJhdmVsIjoi7Jes7ZaJIn0KICAgICAgICByZXR1cm4gYXdhaXQgc2VsZi5fbmF2ZXJfc2Vh"
    "cmNoKHNlbGYuX3RyYW5zbGF0ZV9rZXl3b3JkKGtleXdvcmQsIGttKSwKICAgICAgICAgICAgInJl"
    "YWQgdGhlIGtleSBpbmZvcm1hdGlvbiBmcm9tIHNlYXJjaCByZXN1bHRzIGluIEtvcmVhbiIsIF9f"
    "ZXZlbnRfZW1pdHRlcl9fKQoKICAgIGFzeW5jIGRlZiBjaGVja193ZWF0aGVyKHNlbGYsIF9fZXZl"
    "bnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIkNoZWNrIHRvZGF5J3Mgd2VhdGhlciBmcm9t"
    "IE5hdmVyLiBVc2UgZm9yIHdlYXRoZXIsIHRlbXBlcmF0dXJlLCByYWluLCB1bWJyZWxsYSwgZmlu"
    "ZSBkdXN0IHF1ZXN0aW9ucy4iIiIKICAgICAgICBjYWNoZWQgPSBzZWxmLl9nZXRfY2FjaGUoIndl"
    "YXRoZXI6dG9kYXkiKQogICAgICAgIGlmIGNhY2hlZDogcmV0dXJuIGNhY2hlZAogICAgICAgIGFz"
    "eW5jIGRlZiBlbWl0KG1zZywgZG9uZT1GYWxzZSk6CiAgICAgICAgICAgIGlmIF9fZXZlbnRfZW1p"
    "dHRlcl9fOiBhd2FpdCBfX2V2ZW50X2VtaXR0ZXJfXyh7InR5cGUiOiJzdGF0dXMiLCJkYXRhIjp7"
    "ImRlc2NyaXB0aW9uIjptc2csImRvbmUiOmRvbmV9fSkKICAgICAgICBhd2FpdCBlbWl0KCLrgqDs"
    "lKgg7ZmV7J24IOykkS4uLiIpCiAgICAgICAgdHJ5OgogICAgICAgICAgICB3ZWF0aGVyID0gYXdh"
    "aXQgc2VsZi5fYXBpX3NlYXJjaCgi7ISc7Jq4IOyYpOuKmCDrgqDslKgg6riw7JioIOuvuOyEuOuo"
    "vOyngCIsIGtpbmQ9ImF1dG8iLCBfX2V2ZW50X2VtaXR0ZXJfXz1fX2V2ZW50X2VtaXR0ZXJfXykK"
    "ICAgICAgICAgICAgYXdhaXQgZW1pdCgi7JmE66OMISIsIGRvbmU9VHJ1ZSkKICAgICAgICAgICAg"
    "aWYgd2VhdGhlciBhbmQgIuqygOyDiSDqsrDqs7wiIG5vdCBpbiB3ZWF0aGVyWzo4XSBhbmQgIuyY"
    "pOulmCIgbm90IGluIHdlYXRoZXJbOjZdOgogICAgICAgICAgICAgICAgc2VsZi5fc2V0X2NhY2hl"
    "KCJ3ZWF0aGVyOnRvZGF5Iiwgd2VhdGhlcikKICAgICAgICAgICAgcmV0dXJuIHdlYXRoZXIgb3Ig"
    "IuuCoOyUqCDsoJXrs7Trpbwg6rCA7KC47Jik7KeAIOuqu+2WiOyKteuLiOuLpC4iCiAgICAgICAg"
    "ZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgICAgICBhd2FpdCBlbWl0KCLsmKTrpZgiLCBk"
    "b25lPVRydWUpCiAgICAgICAgICAgIHJldHVybiAi64Kg7JSoIO2ZleyduCDsmKTrpZg6ICIgKyBz"
    "dHIoZSkKCiAgICBhc3luYyBkZWYgY2hlY2tfcHJpY2Uoc2VsZiwgcHJvZHVjdCwgX19ldmVudF9l"
    "bWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiU2VhcmNoIHByb2R1Y3QgcHJpY2VzIG9uIE5hdmVy"
    "IFNob3BwaW5nLgogICAgICAgIDpwYXJhbSBwcm9kdWN0OiBQcm9kdWN0IG5hbWUKICAgICAgICAi"
    "IiIKICAgICAgICBpZiBub3QgcHJvZHVjdC5zdHJpcCgpOiByZXR1cm4gIuyDge2SiOuqheydhCDs"
    "noXroKXtlZjshLjsmpQuIgogICAgICAgIHBtID0geyJhaXJwb2RzIjoi7JeQ7Ja07YyfIiwiYWly"
    "cG9kcyBwcm8iOiLsl5DslrTtjJ8g7ZSE66GcIiwiaXBob25lIjoi7JWE7J207Y+wIiwiZ2FsYXh5"
    "Ijoi6rCk65+t7IucIiwKICAgICAgICAgICAgICAibWFjYm9vayI6Iuunpeu2gSIsImlwYWQiOiLs"
    "lYTsnbTtjKjrk5wiLCJuaW50ZW5kbyBzd2l0Y2giOiLri4zthZDrj4Qg7Iqk7JyE7LmYIiwicHM1"
    "Ijoi7ZSM66CI7J207Iqk7YWM7J207IWYNSJ9CiAgICAgICAgcmV0dXJuIGF3YWl0IHNlbGYuX25h"
    "dmVyX3NlYXJjaChzZWxmLl90cmFuc2xhdGVfa2V5d29yZChwcm9kdWN0LCBwbSkgKyAiIOqwgOqy"
    "qSIsCiAgICAgICAgICAgICJmaW5kIGxvd2VzdCBwcmljZSwgc3RvcmUgbmFtZSwgZGVsaXZlcnkg"
    "aW5mby4gUmVzcG9uZCBpbiBLb3JlYW4uIiwgX19ldmVudF9lbWl0dGVyX18pCgogICAgYXN5bmMg"
    "ZGVmIGNoZWNrX3N0b2NrKHNlbGYsIGNvbXBhbnksIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgog"
    "ICAgICAgICIiIkNoZWNrIHN0b2NrIHByaWNlIGFuZCBtYXJrZXQgZGF0YS4KICAgICAgICA6cGFy"
    "YW0gY29tcGFueTogQ29tcGFueSBuYW1lCiAgICAgICAgIiIiCiAgICAgICAgaWYgbm90IGNvbXBh"
    "bnkuc3RyaXAoKTogcmV0dXJuICLtmozsgqzrqoXsnYQg7J6F66Cl7ZWY7IS47JqULiIKICAgICAg"
    "ICBzbSA9IHsic2Ftc3VuZyI6IuyCvOyEseyghOyekCIsInNrIGh5bml4IjoiU0vtlZjsnbTri4ns"
    "iqQiLCJhcHBsZSI6IuyVoO2UjCDso7zqsIAiLCJudmlkaWEiOiLsl5TruYTrlJTslYQg7KO86rCA"
    "IiwKICAgICAgICAgICAgICAidGVzbGEiOiLthYzsiqzrnbwg7KO86rCAIiwia29zcGkiOiLsvZTs"
    "iqTtlLwiLCJrb3NkYXEiOiLsvZTsiqTri6UiLCJuYXNkYXEiOiLrgpjsiqTri6UifQogICAgICAg"
    "IGsgPSBzZWxmLl90cmFuc2xhdGVfa2V5d29yZChjb21wYW55LCBzbSkKICAgICAgICBpZiAi7KO8"
    "6rCAIiBub3QgaW4gayBhbmQgayBub3QgaW4gWyLsvZTsiqTtlLwiLCLsvZTsiqTri6UiLCLrgpjs"
    "iqTri6UiXTogayArPSAiIOyjvOqwgCIKICAgICAgICByZXR1cm4gYXdhaXQgc2VsZi5fbmF2ZXJf"
    "c2VhcmNoKGssICJyZWFkIHN0b2NrIHByaWNlLCBjaGFuZ2UsIG1hcmtldCBjYXAuIFJlc3BvbmQg"
    "aW4gS29yZWFuLiIsIF9fZXZlbnRfZW1pdHRlcl9fKQoKICAgIGFzeW5jIGRlZiBjaGVja19uZXdz"
    "KHNlbGYsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIkNoZWNrIHRvZGF5J3Mg"
    "dG9wIG5ld3MgaGVhZGxpbmVzIGZyb20gTmF2ZXIgTmV3cy4iIiIKICAgICAgICBjYWNoZWQgPSBz"
    "ZWxmLl9nZXRfY2FjaGUoIm5ld3M6dG9kYXkiKQogICAgICAgIGlmIGNhY2hlZDogcmV0dXJuIGNh"
    "Y2hlZAogICAgICAgIHJlc3VsdCA9IGF3YWl0IHNlbGYuX2FwaV9zZWFyY2goIuyYpOuKmCDso7zs"
    "mpQg64m07IqkIiwga2luZD0ibmV3cyIsIGRpc3BsYXk9NSwgX19ldmVudF9lbWl0dGVyX189X19l"
    "dmVudF9lbWl0dGVyX18pCiAgICAgICAgc2VsZi5fc2V0X2NhY2hlKCJuZXdzOnRvZGF5IiwgcmVz"
    "dWx0KQogICAgICAgIHJldHVybiByZXN1bHQKCiAgICBhc3luYyBkZWYgY2hlY2tfZXhjaGFuZ2Vf"
    "cmF0ZShzZWxmLCBjdXJyZW5jeT0iZG9sbGFyIiwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAg"
    "ICAgICAgIiIiQ2hlY2sgY3VycmVudCBleGNoYW5nZSByYXRlcy4KICAgICAgICA6cGFyYW0gY3Vy"
    "cmVuY3k6IEN1cnJlbmN5IG5hbWUgKGRvbGxhciwgeWVuLCBldXJvLCB5dWFuKQogICAgICAgICIi"
    "IgogICAgICAgIHJtID0geyJkb2xsYXIiOiLri6zrn6wg7ZmY7JyoIiwidXNkIjoi64us65+sIO2Z"
    "mOycqCIsInllbiI6IuyXlO2ZlCDtmZjsnKgiLCJldXJvIjoi7Jyg66GcIO2ZmOycqCIsInl1YW4i"
    "OiLsnITslYgg7ZmY7JyoIiwicG91bmQiOiLtjIzsmrTrk5wg7ZmY7JyoIn0KICAgICAgICByZXR1"
    "cm4gYXdhaXQgc2VsZi5fbmF2ZXJfc2VhcmNoKHNlbGYuX3RyYW5zbGF0ZV9rZXl3b3JkKGN1cnJl"
    "bmN5LCBybSksCiAgICAgICAgICAgICJyZWFkIGV4Y2hhbmdlIHJhdGUsIGNoYW5nZSBmcm9tIHll"
    "c3RlcmRheS4gUmVzcG9uZCBpbiBLb3JlYW4uIiwgX19ldmVudF9lbWl0dGVyX18pCgogICAgYXN5"
    "bmMgZGVmIGNoZWNrX3Nwb3J0cyhzZWxmLCBzcG9ydD0ic29jY2VyIiwgX19ldmVudF9lbWl0dGVy"
    "X189Tm9uZSk6CiAgICAgICAgIiIiQ2hlY2sgc3BvcnRzIHNjb3JlcyBhbmQgcmVzdWx0cy4KICAg"
    "ICAgICA6cGFyYW0gc3BvcnQ6IFNwb3J0IHR5cGUgKHNvY2NlciwgYmFzZWJhbGwsIGJhc2tldGJh"
    "bGwsIGtibywgZXBsKQogICAgICAgICIiIgogICAgICAgIHNtID0geyJzb2NjZXIiOiLstpXqtawg"
    "6rK96riw6rKw6rO8IiwiYmFzZWJhbGwiOiLslbzqtawg6rK96riw6rKw6rO8IiwiYmFza2V0YmFs"
    "bCI6IuuGjeq1rCDqsr3quLDqsrDqs7wiLAogICAgICAgICAgICAgICJrYm8iOiJLQk8g6rK96riw"
    "6rKw6rO8IiwiZXBsIjoiRVBMIOqysOqzvCIsIm5iYSI6Ik5CQSDqsrDqs7wifQogICAgICAgIHJl"
    "dHVybiBhd2FpdCBzZWxmLl9uYXZlcl9zZWFyY2goc2VsZi5fdHJhbnNsYXRlX2tleXdvcmQoc3Bv"
    "cnQsIHNtKSwKICAgICAgICAgICAgInJlYWQgcmVjZW50IG1hdGNoIHJlc3VsdHMsIHNjb3Jlcywg"
    "c3RhbmRpbmdzLiBSZXNwb25kIGluIEtvcmVhbi4iLCBfX2V2ZW50X2VtaXR0ZXJfXykKCiAgICBh"
    "c3luYyBkZWYgc3VtbWFyaXplX3lvdXR1YmUoc2VsZiwgdXJsLCBfX2V2ZW50X2VtaXR0ZXJfXz1O"
    "b25lKToKICAgICAgICAiIiJTdW1tYXJpemUgYSBZb3VUdWJlIHZpZGVvLgogICAgICAgIDpwYXJh"
    "bSB1cmw6IFlvdVR1YmUgVVJMCiAgICAgICAgIiIiCiAgICAgICAgaWYgInlvdXR1YmUuY29tIiBu"
    "b3QgaW4gdXJsIGFuZCAieW91dHUuYmUiIG5vdCBpbiB1cmw6IHJldHVybiAiWW91VHViZSBVUkzs"
    "nbQg7JWE64uZ64uI64ukLiIKICAgICAgICByZXR1cm4gYXdhaXQgc2VsZi5icm93c2UodXJsICsg"
    "IiBzdW1tYXJpemUgdmlkZW8gdGl0bGUsIGNoYW5uZWwsIHZpZXcgY291bnQsIG1haW4gY29udGVu"
    "dCBpbiBLb3JlYW4uIiwgX19ldmVudF9lbWl0dGVyX18pCgogICAgYXN5bmMgZGVmIG9wZW5fYW5k"
    "X3N1bW1hcml6ZShzZWxmLCB1cmwsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIi"
    "Ik9wZW4gYSB3ZWJwYWdlIGFuZCBzdW1tYXJpemUgaW4gS29yZWFuLgogICAgICAgIDpwYXJhbSB1"
    "cmw6IEZ1bGwgVVJMCiAgICAgICAgIiIiCiAgICAgICAgaWYgbm90IHVybC5zdGFydHN3aXRoKCgi"
    "aHR0cDovLyIsImh0dHBzOi8vIikpOiByZXR1cm4gIlVSTOydgCBodHRwOi8v66GcIOyLnOyeke2V"
    "tOyVvCDtlanri4jri6QuIgogICAgICAgIGJsb2NrZWQgPSBbImNvdXBhbmcuY29tIiwiZ21hcmtl"
    "dC5jby5rciIsIjExc3QuY28ua3IiLCJhdWN0aW9uLmNvLmtyIl0KICAgICAgICBpZiBhbnkocyBp"
    "biB1cmwubG93ZXIoKSBmb3IgcyBpbiBibG9ja2VkKTogcmV0dXJuICLsnbQg7IKs7J207Yq464qU"
    "IOywqOuLqOuQqeuLiOuLpC4gY2hlY2tfcHJpY2Xrpbwg7IKs7Jqp7ZWY7IS47JqULiIKICAgICAg"
    "ICBpZiAieW91dHViZS5jb20iIGluIHVybCBvciAieW91dHUuYmUiIGluIHVybDogcmV0dXJuIGF3"
    "YWl0IHNlbGYuc3VtbWFyaXplX3lvdXR1YmUodXJsLCBfX2V2ZW50X2VtaXR0ZXJfXykKICAgICAg"
    "ICByZXR1cm4gYXdhaXQgc2VsZi5icm93c2UodXJsICsgIiBzdW1tYXJpemUgdGhlIG1haW4gY29u"
    "dGVudCBpbiBLb3JlYW4iLCBfX2V2ZW50X2VtaXR0ZXJfXykKCiAgICBhc3luYyBkZWYgbXVsdGlf"
    "YWdlbnRfYnJvd3NlKHNlbGYsIHRhc2ssIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUsIF9fdXNlcl9f"
    "PXt9KToKICAgICAgICAiIiJNdWx0aS1BZ2VudCDrqqjrk5zroZwg67O17J6h7ZWcIOyekeyXhSDs"
    "iJjtlokuCiAgICAgICAgOnBhcmFtIHRhc2s6IOyekeyXhSDrgrTsmqkKICAgICAgICAiIiIKICAg"
    "ICAgICBhc3luYyBkZWYgZW1pdChtc2csIGRvbmU9RmFsc2UpOgogICAgICAgICAgICBpZiBfX2V2"
    "ZW50X2VtaXR0ZXJfXzogYXdhaXQgX19ldmVudF9lbWl0dGVyX18oeyJ0eXBlIjoic3RhdHVzIiwi"
    "ZGF0YSI6eyJkZXNjcmlwdGlvbiI6bXNnLCJkb25lIjpkb25lfX0pCiAgICAgICAgYXdhaXQgZW1p"
    "dCgiTXVsdGktQWdlbnQg7KGw7IKsIOyLnOyekS4uLiIpCiAgICAgICAgdHJ5OgogICAgICAgICAg"
    "ICByZXN1bHQgPSBhd2FpdCBzZWxmLl9wb3N0KCIvYnJvd3NlL211bHRpIiwgeyJ0YXNrIjogdGFz"
    "a30pCiAgICAgICAgICAgIGF3YWl0IGVtaXQoIuyZhOujjCIsIGRvbmU9VHJ1ZSkKICAgICAgICAg"
    "ICAgcmV0dXJuIHJlc3VsdC5nZXQoInN1bW1hcnkiLCByZXN1bHQuZ2V0KCJyZXN1bHQiLCBzdHIo"
    "cmVzdWx0KSkpCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgICAgICBhd2Fp"
    "dCBlbWl0KCLsmKTrpZgiLCBkb25lPVRydWUpCiAgICAgICAgICAgIHJldHVybiAiTXVsdGktQWdl"
    "bnQg7Jik66WYOiAiICsgc3RyKGUpCgogICAgYXN5bmMgZGVmIGNsb3NlX2Jyb3dzZXIoc2VsZiwg"
    "X19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiQ2xvc2UgYnJvd3NlciBzZXNzaW9u"
    "IGFuZCBjbGVhciBjYWNoZS4iIiIKICAgICAgICBzZWxmLl9zZXNzaW9uX2lkID0gTm9uZQogICAg"
    "ICAgIHNlbGYuX2NhY2hlLmNsZWFyKCkKICAgICAgICByZXR1cm4gIuu4jOudvOyasOyggCDshLjs"
    "hZgg7KKF66OMICsg7LqQ7IucIOy0iOq4sO2ZlCDsmYTro4wiCgogICAgYXN5bmMgZGVmIGdldF9t"
    "ZW1vcnkoc2VsZiwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIi7KCA7J6l65Cc"
    "IOyCrOyaqeyekCDsoJXrs7Qg7KGw7ZqMLiIiIgogICAgICAgIGlmIG5vdCBzZWxmLnZhbHZlcy5F"
    "TkFCTEVfTUVNT1JZOiByZXR1cm4gIuuplOuqqOumrCDruYTtmZzshLHtmZQiCiAgICAgICAgdHJ5"
    "OgogICAgICAgICAgICBpbXBvcnQgaHR0cHgsIGpzb24KICAgICAgICAgICAgYXN5bmMgd2l0aCBo"
    "dHRweC5Bc3luY0NsaWVudCh0aW1lb3V0PTEwKSBhcyBjOgogICAgICAgICAgICAgICAgciA9IGF3"
    "YWl0IGMuZ2V0KHNlbGYudmFsdmVzLkJST1dTRVJfQUdFTlRfVVJMICsgIi9tZW1vcnkiLCBoZWFk"
    "ZXJzPXNlbGYuX2hlYWRlcnMoKSkKICAgICAgICAgICAgICAgIHJldHVybiAi8J+TnSDrqZTrqqjr"
    "pqw6XG4iICsganNvbi5kdW1wcyhyLmpzb24oKSwgZW5zdXJlX2FzY2lpPUZhbHNlLCBpbmRlbnQ9"
    "MikKICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6IHJldHVybiAi66mU66qo66asIOyhsO2a"
    "jCDsi6TtjKg6ICIgKyBzdHIoZSkKCiAgICBhc3luYyBkZWYgdXBkYXRlX21lbW9yeShzZWxmLCBp"
    "bmZvLCBfX2V2ZW50X2VtaXR0ZXJfXz1Ob25lKToKICAgICAgICAiIiLsgqzsmqnsnpAg7KCV67O0"
    "IOyggOyepS4KICAgICAgICA6cGFyYW0gaW5mbzog6riw7Ja17ZWgIOygleuztAogICAgICAgICIi"
    "IgogICAgICAgIGlmIG5vdCBzZWxmLnZhbHZlcy5FTkFCTEVfTUVNT1JZOiByZXR1cm4gIuuplOuq"
    "qOumrCDruYTtmZzshLHtmZQiCiAgICAgICAgYm9keSA9IHsiZmFjdHMiOiBbaW5mb1s6MjAwXV19"
    "CiAgICAgICAgZm9yIGxvYyBpbiBbIuyEnOyauCIsIuu2gOyCsCIsIuuMgOq1rCIsIuyduOyynCIs"
    "Iuq0keyjvCIsIuuMgOyghCIsIuyauOyCsCIsIuygnOyjvCJdOgogICAgICAgICAgICBpZiBsb2Mg"
    "aW4gaW5mbzogYm9keVsibG9jYXRpb24iXSA9IGxvYzsgYnJlYWsKICAgICAgICB0cnk6CiAgICAg"
    "ICAgICAgIGF3YWl0IHNlbGYuX3Bvc3QoIi9tZW1vcnkiLCBib2R5KTsgcmV0dXJuICLinIUg6riw"
    "7Ja17ZaI7Iq164uI64ukOiAiICsgaW5mbwogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZTog"
    "cmV0dXJuICLsoIDsnqUg7Iuk7YyoOiAiICsgc3RyKGUpCgogICAgYXN5bmMgZGVmIGNsZWFyX21l"
    "bW9yeShzZWxmLCBfX2V2ZW50X2VtaXR0ZXJfXz1Ob25lKToKICAgICAgICAiIiLsoIDsnqXrkJwg"
    "66qo65OgIOuplOuqqOumrCDsgq3soJwuIiIiCiAgICAgICAgdHJ5OgogICAgICAgICAgICBpbXBv"
    "cnQgaHR0cHgKICAgICAgICAgICAgYXN5bmMgd2l0aCBodHRweC5Bc3luY0NsaWVudCh0aW1lb3V0"
    "PTEwKSBhcyBjOgogICAgICAgICAgICAgICAgYXdhaXQgYy5kZWxldGUoc2VsZi52YWx2ZXMuQlJP"
    "V1NFUl9BR0VOVF9VUkwgKyAiL21lbW9yeSIsIGhlYWRlcnM9c2VsZi5faGVhZGVycygpKQogICAg"
    "ICAgICAgICAgICAgcmV0dXJuICLinIUg66mU66qo66asIOy0iOq4sO2ZlCDsmYTro4wiCiAgICAg"
    "ICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOiByZXR1cm4gIuyCreygnCDsi6TtjKg6ICIgKyBzdHIo"
    "ZSkKCiAgICBhc3luYyBkZWYgbGlzdF9maWxlcyhzZWxmLCBfX2V2ZW50X2VtaXR0ZXJfXz1Ob25l"
    "KToKICAgICAgICAiIiJ+L2FpLXNoYXJlIO2PtOuNlOydmCDtjIzsnbwg66qp66GdIOyhsO2ajC4i"
    "IiIKICAgICAgICBpZiBub3Qgc2VsZi52YWx2ZXMuRU5BQkxFX0ZJTEVfQUNDRVNTOiByZXR1cm4g"
    "Iu2MjOydvCDsoJHqt7wg67mE7Zmc7ISx7ZmUIgogICAgICAgIHRyeToKICAgICAgICAgICAgaW1w"
    "b3J0IGh0dHB4CiAgICAgICAgICAgIGFzeW5jIHdpdGggaHR0cHguQXN5bmNDbGllbnQodGltZW91"
    "dD0xMCkgYXMgYzoKICAgICAgICAgICAgICAgIHIgPSBhd2FpdCBjLmdldChzZWxmLnZhbHZlcy5C"
    "Uk9XU0VSX0FHRU5UX1VSTCArICIvZmlsZXMiLCBoZWFkZXJzPXNlbGYuX2hlYWRlcnMoKSkKICAg"
    "ICAgICAgICAgICAgIGZpbGVzID0gci5qc29uKCkuZ2V0KCJmaWxlcyIsIFtdKQogICAgICAgICAg"
    "ICAgICAgaWYgbm90IGZpbGVzOiByZXR1cm4gIvCfk4Eg7YyM7J28IOyXhuydjCAofi9haS1zaGFy"
    "ZeyXkCDtjIzsnbzsnYQg64Sj7Ja07KO87IS47JqUKSIKICAgICAgICAgICAgICAgIGxpbmVzID0g"
    "WyLwn5OBIO2MjOydvCDrqqnroZ06Il0KICAgICAgICAgICAgICAgIGZvciBmIGluIGZpbGVzOgog"
    "ICAgICAgICAgICAgICAgICAgIGxpbmVzLmFwcGVuZCgiICDigKIgIiArIGZbIm5hbWUiXSArICIg"
    "KCIgKyBzdHIocm91bmQoZlsic2l6ZSJdLzEwMjQsIDEpKSArICJLQikiKQogICAgICAgICAgICAg"
    "ICAgcmV0dXJuICJcbiIuam9pbihsaW5lcykKICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6"
    "IHJldHVybiAi7KGw7ZqMIOyLpO2MqDogIiArIHN0cihlKQoKICAgIGFzeW5jIGRlZiByZWFkX2Zp"
    "bGUoc2VsZiwgZmlsZW5hbWUsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIuuh"
    "nOy7rCDtjIzsnbwg7J296riwLgogICAgICAgIDpwYXJhbSBmaWxlbmFtZTog7YyM7J2866qFCiAg"
    "ICAgICAgIiIiCiAgICAgICAgaWYgbm90IHNlbGYudmFsdmVzLkVOQUJMRV9GSUxFX0FDQ0VTUzog"
    "cmV0dXJuICLtjIzsnbwg7KCR6re8IOu5hO2ZnOyEse2ZlCIKICAgICAgICB0cnk6CiAgICAgICAg"
    "ICAgIGltcG9ydCBodHRweAogICAgICAgICAgICBhc3luYyB3aXRoIGh0dHB4LkFzeW5jQ2xpZW50"
    "KHRpbWVvdXQ9MzApIGFzIGM6CiAgICAgICAgICAgICAgICByID0gYXdhaXQgYy5nZXQoc2VsZi52"
    "YWx2ZXMuQlJPV1NFUl9BR0VOVF9VUkwgKyAiL2ZpbGVzLyIgKyBmaWxlbmFtZSwgaGVhZGVycz1z"
    "ZWxmLl9oZWFkZXJzKCkpCiAgICAgICAgICAgICAgICBpZiByLnN0YXR1c19jb2RlID09IDQwNDog"
    "cmV0dXJuICLinYwg7YyM7J28IOyXhuydjDogIiArIGZpbGVuYW1lCiAgICAgICAgICAgICAgICBy"
    "ZXR1cm4gIvCfk4QgIiArIGZpbGVuYW1lICsgIjpcbiIgKyByLmpzb24oKS5nZXQoImNvbnRlbnQi"
    "LCAiIilbOjUwMDBdCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOiByZXR1cm4gIuydveq4"
    "sCDsi6TtjKg6ICIgKyBzdHIoZSkKCiAgICBhc3luYyBkZWYgc2F2ZV9maWxlKHNlbGYsIGZpbGVu"
    "YW1lLCBjb250ZW50LCBfX2V2ZW50X2VtaXR0ZXJfXz1Ob25lKToKICAgICAgICAiIiLroZzsu6wg"
    "7YyM7J28IOyggOyepS4KICAgICAgICA6cGFyYW0gZmlsZW5hbWU6IO2MjOydvOuqhQogICAgICAg"
    "IDpwYXJhbSBjb250ZW50OiDsoIDsnqXtlaAg64K07JqpCiAgICAgICAgIiIiCiAgICAgICAgaWYg"
    "bm90IHNlbGYudmFsdmVzLkVOQUJMRV9GSUxFX0FDQ0VTUzogcmV0dXJuICLtjIzsnbwg7KCR6re8"
    "IOu5hO2ZnOyEse2ZlCIKICAgICAgICB0cnk6CiAgICAgICAgICAgIGltcG9ydCBodHRweAogICAg"
    "ICAgICAgICBhc3luYyB3aXRoIGh0dHB4LkFzeW5jQ2xpZW50KHRpbWVvdXQ9MzApIGFzIGM6CiAg"
    "ICAgICAgICAgICAgICByID0gYXdhaXQgYy5wb3N0KHNlbGYudmFsdmVzLkJST1dTRVJfQUdFTlRf"
    "VVJMICsgIi9maWxlcy8iICsgZmlsZW5hbWUsIGpzb249eyJjb250ZW50Ijpjb250ZW50fSwgaGVh"
    "ZGVycz1zZWxmLl9oZWFkZXJzKCkpCiAgICAgICAgICAgICAgICBkID0gci5qc29uKCkKICAgICAg"
    "ICAgICAgICAgIGlmIGQuZ2V0KCJzdWNjZXNzIik6IHJldHVybiAi4pyFIOyggOyepTogIiArIGZp"
    "bGVuYW1lICsgIiAoIiArIHN0cihkLmdldCgic2l6ZSIsMCkpICsgIkIpIgogICAgICAgICAgICAg"
    "ICAgcmV0dXJuICLinYwg7Iuk7YyoOiAiICsgc3RyKGQpCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlv"
    "biBhcyBlOiByZXR1cm4gIuyggOyepSDsi6TtjKg6ICIgKyBzdHIoZSkKCiAgICBhc3luYyBkZWYg"
    "Y29tcGFyZV9zaXRlcyhzZWxmLCB0YXNrLCB1cmxzPSIiLCBfX2V2ZW50X2VtaXR0ZXJfXz1Ob25l"
    "KToKICAgICAgICAiIiLsl6zrn6wg7IKs7J207Yq4IOu5hOq1kCDrtoTshJ0gKOycoOujjCBBUEkg"
    "6raM7J6lKS4KICAgICAgICA6cGFyYW0gdGFzazog67mE6rWQIOuCtOyaqQogICAgICAgIDpwYXJh"
    "bSB1cmxzOiBVUkzrk6Qg7Im87ZGcIOq1rOu2hCAo67mE7JuM65GQ66m0IOyekOuPmSkKICAgICAg"
    "ICAiIiIKICAgICAgICBpZiBub3Qgc2VsZi52YWx2ZXMuRU5BQkxFX01VTFRJVEFCOiByZXR1cm4g"
    "IuupgO2LsO2DrSDruYTtmZzshLHtmZQiCiAgICAgICAgaWYgX19ldmVudF9lbWl0dGVyX186IGF3"
    "YWl0IF9fZXZlbnRfZW1pdHRlcl9fKHsidHlwZSI6InN0YXR1cyIsImRhdGEiOnsiZGVzY3JpcHRp"
    "b24iOiLrqYDti7Dtg60g67mE6rWQIOyLnOyekS4uLiIsImRvbmUiOkZhbHNlfX0pCiAgICAgICAg"
    "dXJsX2xpc3QgPSBbdS5zdHJpcCgpIGZvciB1IGluIHVybHMuc3BsaXQoIiwiKSBpZiB1LnN0cmlw"
    "KCldWzpzZWxmLnZhbHZlcy5NQVhfVEFCU10gaWYgdXJscyBlbHNlIFtdCiAgICAgICAgdHJ5Ogog"
    "ICAgICAgICAgICBpbXBvcnQgaHR0cHgKICAgICAgICAgICAgYm9keSA9IHsidGFzayI6dGFzaywi"
    "dXJscyI6dXJsX2xpc3QsIm1heF9zdGVwc19wZXJfdGFiIjo4fQogICAgICAgICAgICBpZiBzZWxm"
    "LnZhbHZlcy5MTE1fUFJPVklERVI6IGJvZHlbInByb3ZpZGVyIl0gPSBzZWxmLnZhbHZlcy5MTE1f"
    "UFJPVklERVIKICAgICAgICAgICAgaWYgc2VsZi52YWx2ZXMuTExNX0FQSV9LRVk6IGJvZHlbImFw"
    "aV9rZXkiXSA9IHNlbGYudmFsdmVzLkxMTV9BUElfS0VZCiAgICAgICAgICAgIGlmIHNlbGYudmFs"
    "dmVzLkxMTV9NT0RFTDogYm9keVsibW9kZWwiXSA9IHNlbGYudmFsdmVzLkxMTV9NT0RFTAogICAg"
    "ICAgICAgICBhc3luYyB3aXRoIGh0dHB4LkFzeW5jQ2xpZW50KHRpbWVvdXQ9c2VsZi52YWx2ZXMu"
    "UkVRVUVTVF9USU1FT1VUKSBhcyBjOgogICAgICAgICAgICAgICAgciA9IGF3YWl0IGMucG9zdChz"
    "ZWxmLnZhbHZlcy5CUk9XU0VSX0FHRU5UX1VSTCArICIvYnJvd3NlL211bHRpdGFiIiwganNvbj1i"
    "b2R5LCBoZWFkZXJzPXNlbGYuX2hlYWRlcnMoKSkKICAgICAgICAgICAgICAgIGRhdGEgPSByLmpz"
    "b24oKQogICAgICAgICAgICBpZiBfX2V2ZW50X2VtaXR0ZXJfXzogYXdhaXQgX19ldmVudF9lbWl0"
    "dGVyX18oeyJ0eXBlIjoic3RhdHVzIiwiZGF0YSI6eyJkZXNjcmlwdGlvbiI6IuyZhOujjCIsImRv"
    "bmUiOlRydWV9fSkKICAgICAgICAgICAgaWYgZGF0YS5nZXQoInN1Y2Nlc3MiKToKICAgICAgICAg"
    "ICAgICAgIHRhYnMgPSBkYXRhLmdldCgidGFicyIsW10pCiAgICAgICAgICAgICAgICBzb3VyY2Vz"
    "ID0gIlxuIi5qb2luKFsiICDigKIg7YOtIiArIHN0cih0WyJ0YWIiXSkgKyAiOiAiICsgdFsidXJs"
    "Il0gZm9yIHQgaW4gdGFic10pCiAgICAgICAgICAgICAgICByZXR1cm4gZGF0YS5nZXQoInN1bW1h"
    "cnkiLCIiKSArICJcblxu8J+TkSDssLjsobA6XG4iICsgc291cmNlcwogICAgICAgICAgICByZXR1"
    "cm4gIuyLpO2MqDogIiArIGRhdGEuZ2V0KCJlcnJvciIsIiIpCiAgICAgICAgZXhjZXB0IEV4Y2Vw"
    "dGlvbiBhcyBlOgogICAgICAgICAgICBpZiBfX2V2ZW50X2VtaXR0ZXJfXzogYXdhaXQgX19ldmVu"
    "dF9lbWl0dGVyX18oeyJ0eXBlIjoic3RhdHVzIiwiZGF0YSI6eyJkZXNjcmlwdGlvbiI6IuyLpO2M"
    "qCIsImRvbmUiOlRydWV9fSkKICAgICAgICAgICAgcmV0dXJuICLrqYDti7Dtg60g7Jik66WYOiAi"
    "ICsgc3RyKGUpCg=="
)
dest = os.environ.get('AGENT_DIR','') + '/openwebui_tool.py'
with open(dest, 'w', encoding='utf-8') as f:
    f.write(base64.b64decode(b64).decode('utf-8'))
print('  ✅ openwebui_tool.py 생성 완료')
WRITE_TOOL
ok "FILE 5/6  openwebui_tool.py"

############################################
# 5-1. openwebui_tool.py 위키피디아 검색 패치
# 검색 우선순위: 네이버 → 다음 → 위키피디아(한국어) → 위키피디아(영어)
# + search_wikipedia() Tool 신규 추가
############################################
step "5-1/9  위키피디아 검색 우선순위 패치"

python3 - "${AGENT_DIR}" << 'WIKI_PATCH'
import re, sys

tool_path = sys.argv[1] + '/openwebui_tool.py'
try:
    with open(tool_path, 'r', encoding='utf-8') as f:
        code = f.read()
except FileNotFoundError:
    print(f"  ❌ 파일 없음: {tool_path}")
    sys.exit(1)

# ── 패치 1: _naver_search 폴백 체인에 위키피디아 추가 ──────────────────
# 기존: 네이버 → 다음
# 변경: 네이버 → 다음 → 위키피디아(한국어) → 위키피디아(영어)
OLD_FALLBACK = '''        if "검색 결과 없음" in result or "CAPTCHA" in result:
            result = await self.browse("https://search.daum.net/search?q=" + encoded + " " + instruction, __event_emitter__)
        self._set_cache("search:" + query_kr, result)
        return result'''

NEW_FALLBACK = '''        if "검색 결과 없음" in result or "CAPTCHA" in result:
            result = await self.browse("https://search.daum.net/search?q=" + encoded + " " + instruction, __event_emitter__)
        # [WIKIPEDIA] 네이버/다음 결과가 불충분하면 위키피디아 보완 검색
        WIKI_INSUFFICIENT = ("검색 결과 없음", "CAPTCHA", "결과가 없", "찾을 수 없", "오류")
        if any(kw in result for kw in WIKI_INSUFFICIENT):
            wiki_kr = await self.browse(
                "https://ko.wikipedia.org/w/index.php?search=" + encoded +
                " " + instruction + " Respond in Korean.", __event_emitter__)
            if not any(kw in wiki_kr for kw in WIKI_INSUFFICIENT):
                result = wiki_kr
            else:
                wiki_en = await self.browse(
                    "https://en.wikipedia.org/w/index.php?search=" + encoded +
                    " " + instruction + " Summarize in Korean.", __event_emitter__)
                if not any(kw in wiki_en for kw in WIKI_INSUFFICIENT):
                    result = wiki_en
        self._set_cache("search:" + query_kr, result)
        return result'''

if OLD_FALLBACK in code:
    code = code.replace(OLD_FALLBACK, NEW_FALLBACK)
    print("  ✅ 패치 1: _naver_search 폴백 체인 → 위키피디아 추가됨")
else:
    print("  ⚠️  패치 1: 대상 코드 불일치 — 수동 확인 필요")

# ── 패치 2: _is_encyclopedic_query() 헬퍼 추가 ──────────────────────────
# _translate_keyword 바로 앞에 삽입
WIKI_HELPER = '''    def _is_encyclopedic_query(self, text: str) -> bool:
        """백과사전형 질문 감지 — 위키피디아를 우선 검색할 기준"""
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
        """스마트 검색: 백과사전형 → 위키피디아 우선, 실시간 → 네이버 우선"""
        encoded = __import__('urllib').parse.quote(query)
        cached = self._get_cache("smart:" + query)
        if cached: return cached
        INSUFFICIENT = ("검색 결과 없음", "CAPTCHA", "결과가 없", "찾을 수 없", "오류")

        if self._is_encyclopedic_query(query):
            # 백과사전형: 위키피디아(한국어) → 위키피디아(영어) → 네이버
            result = await self.browse(
                "https://ko.wikipedia.org/w/index.php?search=" + encoded +
                " " + instruction + " Respond in Korean.", __event_emitter__)
            if any(kw in result for kw in INSUFFICIENT):
                result = await self.browse(
                    "https://en.wikipedia.org/w/index.php?search=" + encoded +
                    " " + instruction + " Summarize in Korean.", __event_emitter__)
            if any(kw in result for kw in INSUFFICIENT):
                result = await self._naver_search(query, instruction, __event_emitter__)
        else:
            # 실시간형: 네이버 → 다음 → 위키피디아
            result = await self._naver_search(query, instruction, __event_emitter__)

        self._set_cache("smart:" + query, result)
        return result

'''

TARGET = '    def _translate_keyword(self, keyword, keyword_map):'
if TARGET in code:
    code = code.replace(TARGET, WIKI_HELPER + TARGET)
    print("  ✅ 패치 2: _is_encyclopedic_query() + _smart_search() 헬퍼 추가됨")
else:
    print("  ⚠️  패치 2: _translate_keyword 위치 불일치 — 수동 확인 필요")

# ── 패치 3: search_wikipedia() Tool 신규 추가 ───────────────────────────
# search_naver() 바로 다음에 삽입
WIKI_TOOL = '''
    async def search_wikipedia(self, keyword, __event_emitter__=None):
        """Search Wikipedia for encyclopedic knowledge (history, science, people, concepts, definitions).
        Tries Korean Wikipedia first, then English Wikipedia as fallback.
        :param keyword: Search keyword (Korean or English)
        """
        if not keyword.strip(): return "검색어를 입력하세요."
        encoded = __import__('urllib').parse.quote(keyword)
        cached = self._get_cache("wiki:" + keyword)
        if cached: return cached
        INSUFFICIENT = ("검색 결과 없음", "CAPTCHA", "결과가 없", "찾을 수 없", "오류", "결과 없음")

        async def emit(msg, done=False):
            if __event_emitter__:
                await __event_emitter__({"type": "status", "data": {"description": msg, "done": done}})

        await emit("🔍 위키피디아(한국어) 검색 중...")
        # 1순위: 한국어 위키피디아 직접 접근
        result = await self.browse(
            "https://ko.wikipedia.org/wiki/" + encoded +
            " 이 문서의 개요, 주요 내용, 핵심 사실을 한국어로 요약하세요.", __event_emitter__)

        if any(kw in result for kw in INSUFFICIENT):
            await emit("🔍 위키피디아(한국어) 검색으로 재시도...")
            # 2순위: 한국어 위키피디아 검색
            result = await self.browse(
                "https://ko.wikipedia.org/w/index.php?search=" + encoded +
                " 검색 결과 중 가장 관련성 높은 항목의 내용을 한국어로 요약하세요.", __event_emitter__)

        if any(kw in result for kw in INSUFFICIENT):
            await emit("🔍 위키피디아(영어) 검색 중...")
            # 3순위: 영어 위키피디아 검색 후 한국어로 번역 요약
            result = await self.browse(
                "https://en.wikipedia.org/w/index.php?search=" + encoded +
                " Summarize the most relevant article content in Korean.", __event_emitter__)

        if any(kw in result for kw in INSUFFICIENT):
            await emit("🔍 네이버 보완 검색 중...")
            # 4순위: 네이버 폴백
            result = await self._naver_search(keyword,
                "백과사전 정보를 찾아 한국어로 요약하세요.", __event_emitter__)

        self._set_cache("wiki:" + keyword, result)
        await emit("완료", done=True)
        return result

'''

INSERT_AFTER = '            "read the key information from search results in Korean", __event_emitter__)\n'
if INSERT_AFTER in code:
    code = code.replace(INSERT_AFTER, INSERT_AFTER + WIKI_TOOL, 1)
    print("  ✅ 패치 3: search_wikipedia() Tool 추가됨")
else:
    print("  ⚠️  패치 3: search_naver 삽입 위치 불일치 — 수동 확인 필요")

# ── 패치 4: Valves에 WIKIPEDIA_PRIORITY 옵션 추가 ─────────────────────────
OLD_VALVE_END = '        LLM_MODEL: str = Field(default="", description="모델명 (비워두면 기본값)")'
NEW_VALVE_END = '''        LLM_MODEL: str = Field(default="", description="모델명 (비워두면 기본값)")
        WIKIPEDIA_PRIORITY: bool = Field(default=True, description="백과사전형 질문에 위키피디아 우선 검색 활성화")
        WIKIPEDIA_LANG: str = Field(default="ko", description="위키피디아 언어 코드 (ko=한국어, en=영어, ja=일본어)")'''

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
info "  실시간 정보: 네이버 → 다음 → 위키피디아(한국어) → 위키피디아(영어)"
info "  백과사전형 : 위키피디아(한국어) → 위키피디아(영어) → 네이버"
info "신규 Tool   : search_wikipedia(keyword)"

############################################
# 5-2. openwebui_tool.py 신규 Tool 5개
# ⑩ 스크린샷  ⑪ 지도검색  ⑫ 파일다운로드
# ⑬ Excel/CSV 내보내기  ⑭ 가격/재고 모니터링
############################################
step "5-2/9  Tool 업그레이드 — 신규 5개 Tool"

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
                            interval_minutes: int = 60, __event_emitter__=None):
        \"\"\"상품 가격·재고·지표 모니터링 등록. '5만원 되면 알려줘' / '재고 생기면 알림'.
        :param url: 모니터링할 웹 페이지 URL
        :param keyword: 감지 항목 (예: 가격, 재고, 환율)
        :param target_value: 목표값 (예: 50000) — 포함 시 트리거. 비워두면 변동만 기록.
        :param interval_minutes: 확인 주기 (분, 5~1440, 기본 60)
        \"\"\"
        if not url.strip() or not keyword.strip():
            return "URL과 키워드를 모두 입력하세요."
        async def emit(msg, done=False):
            if __event_emitter__:
                await __event_emitter__({"type":"status","data":{"description":msg,"done":done}})
        await emit(f"🔔 모니터링 등록: {keyword}")
        payload = {"url": url, "keyword": keyword, "target_value": target_value,
                   "label": keyword[:20],
                   "interval_minutes": max(5, min(1440, interval_minutes))}
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

# _call_api에 method 파라미터 추가 (GET 지원)
OLD_CAPI = 'async def _call_api(self, endpoint: str, data: dict'
NEW_CAPI = 'async def _call_api(self, endpoint: str, data: dict = None, method: str = "POST"'
if OLD_CAPI in code and NEW_CAPI not in code:
    code = code.replace(OLD_CAPI, NEW_CAPI)
    ok_list.append('_call_api method 파라미터')

with open(tool_path, 'w', encoding='utf-8') as f: f.write(code)
print(f"  📋 적용: {len(ok_list)}개")
for p in ok_list: print(f"    ✅ {p}")
print(f"  📋 최종 라인: {len(code.splitlines())}")
TOOL_UPGRADE

ok "openwebui_tool.py 업그레이드 완료"
info "신규 Tool: take_screenshot / search_map / download_file / export_to_excel / monitor_price / check_monitors"

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
      - TASK_TIMEOUT=120
      - NAVER_CLIENT_ID=${{NAVER_CLIENT_ID:-}}
      - NAVER_CLIENT_SECRET=${{NAVER_CLIENT_SECRET:-}}
      - TAVILY_API_KEY=${{TAVILY_API_KEY:-}}
      - SEARCH_TIMEOUT=${{SEARCH_TIMEOUT:-15}}
      - SEARCH_CACHE_TTL=${{SEARCH_CACHE_TTL:-300}}
      - MULTI_TIMEOUT=300
      - MAX_CONCURRENT=3
      - ENABLE_REQUEST_SIGNING=false
      - BROWSER_PROXY=
      - BROWSER_POOL_SIZE=0
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
_EXPECTED_SVCS="qdrant openapi-tools open-webui twilio-bot"
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
        "description": "AI 브라우저 에이전트: browse_web으로 웹 작업, search_web으로 검색, search_wikipedia로 백과사전 검색, check_weather로 날씨 확인. Browser Use + Groq 기반."
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
