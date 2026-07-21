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
    "X1RJTUVPVVQiLCAiMzAwIikpICAgICAjIE11bHRpLUFnZW50IOy1nOuMgCAzMDDstIgKTVVMVElf"
    "QlVER0VUX1VTRCA9IGZsb2F0KG9zLmdldGVudigiTVVMVElfQlVER0VUX1VTRCIsICIwIikpICAj"
    "IE11bHRpLUFnZW50IOq4sOuzuCDruYTsmqkg7IOB7ZWcICgwPeustOygnO2VnCkKU1RFUF9USU1F"
    "T1VUID0gaW50KG9zLmdldGVudigiU1RFUF9USU1FT1VUIiwgIjMwIikpICAgICAgICAjIOuLqOyd"
    "vCDsiqTthZ0g7LWc64yAIDMw7LSICgojIOKUgOKUgCBbdjddIOqygOyDiSBBUEkg7YKkICjrhKTs"
    "nbTrsoQgKyBUYXZpbHkpIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApOQVZFUl9DTElFTlRfSUQgICAgID0gb3MuZ2V0ZW52"
    "KCJOQVZFUl9DTElFTlRfSUQiLCAiIikKTkFWRVJfQ0xJRU5UX1NFQ1JFVCA9IG9zLmdldGVudigi"
    "TkFWRVJfQ0xJRU5UX1NFQ1JFVCIsICIiKQpUQVZJTFlfQVBJX0tFWSAgICAgID0gb3MuZ2V0ZW52"
    "KCJUQVZJTFlfQVBJX0tFWSIsICIiKQpTRUFSQ0hfVElNRU9VVCAgICAgID0gaW50KG9zLmdldGVu"
    "digiU0VBUkNIX1RJTUVPVVQiLCAiMTUiKSkKU0VBUkNIX0NBQ0hFX1RUTCAgICA9IGludChvcy5n"
    "ZXRlbnYoIlNFQVJDSF9DQUNIRV9UVEwiLCAiMzAwIikpCl9zZWFyY2hfY2FjaGUgPSB7fQoKIyBb"
    "U0VDVVJJVFldIO2XiOyaqSDrj4TrqZTsnbggKOu5iOqwkiA9IOyghOyytCDtl4jsmqkpCkFMTE9X"
    "RURfT1JJR0lOUyA9IG9zLmdldGVudigiQUxMT1dFRF9PUklHSU5TIiwgIiIpLnNwbGl0KCIsIikK"
    "QUxMT1dFRF9PUklHSU5TID0gW28uc3RyaXAoKSBmb3IgbyBpbiBBTExPV0VEX09SSUdJTlMgaWYg"
    "by5zdHJpcCgpXQoKIyBbU0VDVVJJVFldIOywqOuLqCBVUkwg7Yyo7YS0CkJMT0NLRURfVVJMX1BB"
    "VFRFUk5TID0gWwogICAgciJeZmlsZTovLyIsIHIiXmphdmFzY3JpcHQ6IiwgciJeZGF0YToiLAog"
    "ICAgciJeZnRwOi8vIiwgciJeY2hyb21lOi8vIiwgciJeYWJvdXQ6IiwKICAgIHIibG9jYWxob3N0"
    "OlxkKy9hZG1pbiIsIHIiMTI3XC4wXC4wXC4xIiwKICAgIHIiMTY5XC4yNTRcLiIsIHIiMTBcLlxk"
    "K1wuXGQrXC5cZCsiLCAgIyDrgrTrtoAg64Sk7Yq47JuM7YGsCiAgICByIjE5MlwuMTY4XC4iLCBy"
    "IjE3MlwuKDFbNi05XXwyXGR8M1swMV0pXC4iLApdCgojIOKUgOKUgCBSYXRlIExpbWl0ZXIg4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACmxpbWl0ZXIgPSBMaW1pdGVyKGtleV9mdW5j"
    "PWdldF9yZW1vdGVfYWRkcmVzcykKCiMg4pSA4pSAIExMTSDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKbGxtID0gTm9uZQoKZGVmIF9s"
    "b2FkX2FwaV9rZXkoKToKICAgIGlmIEFQSV9LRVk6IHJldHVybiBBUElfS0VZCiAgICB0cnk6CiAg"
    "ICAgICAgcCA9IFBhdGgoIi9hcHAvc2VjcmV0cy9hcGlfa2V5IikKICAgICAgICBpZiBwLmV4aXN0"
    "cygpOiByZXR1cm4gcC5yZWFkX3RleHQoKS5zdHJpcCgpCiAgICBleGNlcHQgRXhjZXB0aW9uOiBw"
    "YXNzCiAgICByZXR1cm4gIiIKCiMgW1NFQ1VSSVRZXSDsg4HsiJgg7Iuc6rCEIOu5hOq1kOuhnCDt"
    "g4DsnbTrsI0g6rO16rKpIOuwqeyngApkZWYgdmVyaWZ5X2FwaV9rZXkocmVxdWVzdDogUmVxdWVz"
    "dCk6CiAgICBhdXRoID0gcmVxdWVzdC5oZWFkZXJzLmdldCgiQXV0aG9yaXphdGlvbiIsICIiKQog"
    "ICAga2V5ID0gX2xvYWRfYXBpX2tleSgpCiAgICBpZiBub3Qga2V5OiByZXR1cm4gVHJ1ZQogICAg"
    "dG9rZW4gPSBhdXRoLnJlcGxhY2UoIkJlYXJlciAiLCAiIikuc3RyaXAoKQogICAgaWYgbm90IHRv"
    "a2VuOgogICAgICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiQVVUSF9NSVNTSU5HfHtyZXF1ZXN0LmNs"
    "aWVudC5ob3N0fXx7cmVxdWVzdC51cmwucGF0aH0iKQogICAgICAgIHJhaXNlIEhUVFBFeGNlcHRp"
    "b24oc3RhdHVzX2NvZGU9NDAxLCBkZXRhaWw9IkF1dGhvcml6YXRpb24gcmVxdWlyZWQiKQogICAg"
    "aWYgbm90IGhtYWMuY29tcGFyZV9kaWdlc3QodG9rZW4uZW5jb2RlKCksIGtleS5lbmNvZGUoKSk6"
    "CiAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJBVVRIX0ZBSUx8e3JlcXVlc3QuY2xpZW50Lmhv"
    "c3R9fHtyZXF1ZXN0LnVybC5wYXRofSIpCiAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbihzdGF0"
    "dXNfY29kZT00MDMsIGRldGFpbD0iSW52YWxpZCBBUEkga2V5IikKICAgIHJldHVybiBUcnVlCgoj"
    "IFtTRUNVUklUWV0gVVJMIOqygOymnQpkZWYgdmFsaWRhdGVfdXJsKHVybDogc3RyKSAtPiBib29s"
    "OgogICAgaWYgbm90IHVybDogcmV0dXJuIFRydWUKICAgIHRyeToKICAgICAgICBwYXJzZWQgPSB1"
    "cmxwYXJzZSh1cmwpCiAgICAgICAgaWYgcGFyc2VkLnNjaGVtZSBub3QgaW4gKCJodHRwIiwgImh0"
    "dHBzIiwgIiIpOgogICAgICAgICAgICByZXR1cm4gRmFsc2UKICAgICAgICBmb3IgcGF0dGVybiBp"
    "biBCTE9DS0VEX1VSTF9QQVRURVJOUzoKICAgICAgICAgICAgaWYgX3JlLnNlYXJjaChwYXR0ZXJu"
    "LCB1cmwsIF9yZS5JR05PUkVDQVNFKToKICAgICAgICAgICAgICAgIHJldHVybiBGYWxzZQogICAg"
    "ICAgIHJldHVybiBUcnVlCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHJldHVybiBGYWxz"
    "ZQoKIyBbU0VDVVJJVFldIOyeheugpSDsg4jri4jtg4DsnbTsp5UKZGVmIHNhbml0aXplX3Rhc2so"
    "dGFzazogc3RyKSAtPiBzdHI6CiAgICAjIOygnOyWtCDrrLjsnpAg7KCc6rGwCiAgICB0YXNrID0g"
    "IiIuam9pbihjIGZvciBjIGluIHRhc2sgaWYgYy5pc3ByaW50YWJsZSgpIG9yIGMgaW4gIlxuXHQi"
    "KQogICAgIyDtlITroaztlITtirgg7J247KCd7IWYIO2MqO2EtCDqsr3qs6AKICAgIGluamVjdGlv"
    "bl9wYXR0ZXJucyA9IFsKICAgICAgICAiaWdub3JlIHByZXZpb3VzIiwgImlnbm9yZSBhYm92ZSIs"
    "ICJkaXNyZWdhcmQiLAogICAgICAgICJzeXN0ZW0gcHJvbXB0IiwgInlvdSBhcmUgbm93IiwgIm5l"
    "dyBpbnN0cnVjdGlvbnMiLAogICAgICAgICJmb3JnZXQgZXZlcnl0aGluZyIsICJvdmVycmlkZSIs"
    "ICJqYWlsYnJlYWsiLAogICAgXQogICAgdGFza19sb3dlciA9IHRhc2subG93ZXIoKQogICAgZm9y"
    "IHAgaW4gaW5qZWN0aW9uX3BhdHRlcm5zOgogICAgICAgIGlmIHAgaW4gdGFza19sb3dlcjoKICAg"
    "ICAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJJTkpFQ1RJT05fQVRURU1QVHx7cH18e3Rhc2tb"
    "OjEwMF19IikKICAgICAgICAgICAgYnJlYWsKICAgIHJldHVybiB0YXNrLnN0cmlwKCkKCgojIFtO"
    "QVZFUi1QUklPUklUWV0g7ZWc6rWt7Ja0IOqwkOyngCArIOuEpOydtOuyhCDsmrDshKAg6rKA7IOJ"
    "IOuhnOyngQpLT1JFQU5fU0VBUkNIX1BBVFRFUk5TID0gewogICAgIuuCoOyUqCI6ICJodHRwczov"
    "L3NlYXJjaC5uYXZlci5jb20vc2VhcmNoLm5hdmVyP3F1ZXJ5PXtxfSvrgqDslKgiLAogICAgIuyj"
    "vOqwgCI6ICJodHRwczovL3NlYXJjaC5uYXZlci5jb20vc2VhcmNoLm5hdmVyP3F1ZXJ5PXtxfSvs"
    "o7zqsIAiLAogICAgIu2ZmOycqCI6ICJodHRwczovL3NlYXJjaC5uYXZlci5jb20vc2VhcmNoLm5h"
    "dmVyP3F1ZXJ5PXtxfSvtmZjsnKgiLAogICAgIuuJtOyKpCI6ICJodHRwczovL25ld3MubmF2ZXIu"
    "Y29tIiwKICAgICLqsIDqsqkiOiAiaHR0cHM6Ly9zZWFyY2gubmF2ZXIuY29tL3NlYXJjaC5uYXZl"
    "cj9xdWVyeT17cX0r6rCA6rKpIiwKfQoKZGVmIGRldGVjdF9rb3JlYW4odGV4dDogc3RyKSAtPiBi"
    "b29sOgogICAgIiIi7ZWc6rWt7Ja0IO2PrO2VqCDsl6zrtoAg6rCQ7KeAIiIiCiAgICByZXR1cm4g"
    "YW55KDB4QUMwMCA8PSBvcmQoYykgPD0gMHhEN0EzIG9yIDB4MzEzMSA8PSBvcmQoYykgPD0gMHgz"
    "MThFIGZvciBjIGluIHRleHQpCgpkZWYgYXBwbHlfbmF2ZXJfcHJpb3JpdHkodGFzazogc3RyKSAt"
    "PiBzdHI6CiAgICAiIiLtlZzqta3slrQg7J6R7JeF7JeQIOuEpOydtOuyhCDsmrDshKAg6rKA7IOJ"
    "IOyngOyLnCDstpTqsIAiIiIKICAgIGlmIG5vdCBkZXRlY3Rfa29yZWFuKHRhc2spOgogICAgICAg"
    "IHJldHVybiB0YXNrCiAgICAKICAgICMg7J2066+4IFVSTOydtCDtj6ztlajrkJwg6rK97JqwIOqx"
    "tOuTnOumrOyngCDslYrsnYwKICAgIGlmICJodHRwOi8vIiBpbiB0YXNrIG9yICJodHRwczovLyIg"
    "aW4gdGFzazoKICAgICAgICByZXR1cm4gdGFzawogICAgCiAgICAjIO2KueyglSDtgqTsm4zrk5wg"
    "66ek7LmtIOKGkiDrhKTsnbTrsoQgVVJMIOyekOuPmSDsgr3snoUKICAgIHRhc2tfbG93ZXIgPSB0"
    "YXNrLmxvd2VyKCkKICAgIGZvciBrZXl3b3JkLCB1cmxfdGVtcGxhdGUgaW4gS09SRUFOX1NFQVJD"
    "SF9QQVRURVJOUy5pdGVtcygpOgogICAgICAgIGlmIGtleXdvcmQgaW4gdGFzazoKICAgICAgICAg"
    "ICAgIyDtgqTsm4zrk5wg7JWe65KkIOy7qO2FjeyKpO2KuCDstpTstpwgKOyYiDogIuyEnOyauCDr"
    "gqDslKgiIOKGkiBxPSLshJzsmrgiKQogICAgICAgICAgICBpbXBvcnQgdXJsbGliLnBhcnNlCiAg"
    "ICAgICAgICAgIHEgPSB0YXNrLnJlcGxhY2Uoa2V5d29yZCwgIiIpLnJlcGxhY2UoIuyVjOugpOyk"
    "mCIsIiIpLnJlcGxhY2UoIu2ZleyduCIsIiIpLnJlcGxhY2UoIuqygOyDiSIsIiIpLnN0cmlwKCkK"
    "ICAgICAgICAgICAgaWYgbm90IHE6IHEgPSB0YXNrLnJlcGxhY2Uoa2V5d29yZCwiIikuc3RyaXAo"
    "KSBvciBrZXl3b3JkCiAgICAgICAgICAgIHVybCA9IHVybF90ZW1wbGF0ZS5mb3JtYXQocT11cmxs"
    "aWIucGFyc2UucXVvdGUocSkpCiAgICAgICAgICAgIHJldHVybiBmIkdvIHRvIHt1cmx9IGFuZCB7"
    "dGFza30uIFJlc3BvbmQgaW4gS29yZWFuLiIKICAgIAogICAgIyDsnbzrsJgg7ZWc6rWt7Ja0IOy/"
    "vOumrCDihpIg64Sk7J2067KEIOqygOyDiSDsmrDshKAKICAgIHJldHVybiBmIlNlYXJjaCBvbiBO"
    "YXZlciAoaHR0cHM6Ly9zZWFyY2gubmF2ZXIuY29tKSBmaXJzdCBmb3I6IHt0YXNrfS4gSWYgTmF2"
    "ZXIgZG9lc24ndCBoYXZlIHRoZSBhbnN3ZXIsIHRyeSBHb29nbGUuIEFsd2F5cyByZXNwb25kIGlu"
    "IEtvcmVhbi4iCgojIFtTRUNVUklUWV0g64+Z7IucIOyLpO2WiSDsoJztlZwKX2FjdGl2ZV90YXNr"
    "cyA9IDAKX2FjdGl2ZV9sb2NrID0gYXN5bmNpby5Mb2NrKCkKTUFYX0NPTkNVUlJFTlQgPSBpbnQo"
    "b3MuZ2V0ZW52KCJNQVhfQ09OQ1VSUkVOVCIsICIzIikpCgpAYXN5bmNjb250ZXh0bWFuYWdlcgph"
    "c3luYyBkZWYgdGFza19zbG90KCk6CiAgICBnbG9iYWwgX2FjdGl2ZV90YXNrcwogICAgYXN5bmMg"
    "d2l0aCBfYWN0aXZlX2xvY2s6CiAgICAgICAgaWYgX2FjdGl2ZV90YXNrcyA+PSBNQVhfQ09OQ1VS"
    "UkVOVDoKICAgICAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbig0MjksIGYiVG9vIG1hbnkgY29u"
    "Y3VycmVudCB0YXNrcyAoe01BWF9DT05DVVJSRU5UfSBtYXgpIikKICAgICAgICBfYWN0aXZlX3Rh"
    "c2tzICs9IDEKICAgIHRyeToKICAgICAgICB5aWVsZAogICAgZmluYWxseToKICAgICAgICBhc3lu"
    "YyB3aXRoIF9hY3RpdmVfbG9jazoKICAgICAgICAgICAgX2FjdGl2ZV90YXNrcyAtPSAxCgpAYXN5"
    "bmNjb250ZXh0bWFuYWdlcgphc3luYyBkZWYgbGlmZXNwYW4oYXBwOiBGYXN0QVBJKToKICAgIGds"
    "b2JhbCBsbG0KICAgICMg66mA7YuwIO2UhOuhnOuwlOydtOuNlCDsnpDrj5kg6rCQ7KeACiAgICB0"
    "cnk6CiAgICAgICAgbGxtID0gY3JlYXRlX2xsbShwcm92aWRlcj1MTE1fUFJPVklERVIpCiAgICAg"
    "ICAgbG9nZ2VyLmluZm8oZiJMTE0gaW5pdDogcHJvdmlkZXI9e2xsbS5wcm92aWRlcn0sIG1vZGVs"
    "PXtnZXRhdHRyKGxsbSwgJ21vZGVsX25hbWUnLCBnZXRhdHRyKGxsbSwgJ21vZGVsJywgJ3Vua25v"
    "d24nKSl9IikKICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICBsb2dnZXIuZXJyb3Io"
    "ZiJMTE0gaW5pdCBmYWlsZWQ6IHtlfSIpCiAgICAgICAgbG9nZ2VyLmVycm9yKCJTZXQgYXQgbGVh"
    "c3Qgb25lIEFQSSBrZXk6IEdST1FfQVBJX0tFWSwgT1BFTkFJX0FQSV9LRVksIEFOVEhST1BJQ19B"
    "UElfS0VZLCBvciBHT09HTEVfQVBJX0tFWSIpCiAgICBsb2dnZXIuaW5mbyhmIlRpbWVvdXRzOiB0"
    "YXNrPXtUQVNLX1RJTUVPVVR9cyBtdWx0aT17TVVMVElfVElNRU9VVH1zIHN0ZXA9e1NURVBfVElN"
    "RU9VVH1zIikKICAgIGxvZ2dlci5pbmZvKGYiQ29uY3VycmVuY3kgbGltaXQ6IHtNQVhfQ09OQ1VS"
    "UkVOVH0iKQogICAgeWllbGQKCmFwcCA9IEZhc3RBUEkodGl0bGU9IkJyb3dzZXIgVXNlIEFnZW50"
    "IiwgdmVyc2lvbj0iNi4yLjAiLCBsaWZlc3Bhbj1saWZlc3BhbiwKICAgICAgICAgICAgICBkb2Nz"
    "X3VybD1Ob25lLCByZWRvY191cmw9Tm9uZSkgICMgW1NFQ1VSSVRZXSBTd2FnZ2VyIFVJIOu5hO2Z"
    "nOyEse2ZlAphcHAuc3RhdGUubGltaXRlciA9IGxpbWl0ZXIKCkBhcHAuZXhjZXB0aW9uX2hhbmRs"
    "ZXIoUmF0ZUxpbWl0RXhjZWVkZWQpCmFzeW5jIGRlZiByYXRlX2xpbWl0X2hhbmRsZXIocmVxdWVz"
    "dCwgZXhjKToKICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiUkFURV9MSU1JVHx7cmVxdWVzdC5jbGll"
    "bnQuaG9zdH18e3JlcXVlc3QudXJsLnBhdGh9IikKICAgIHJldHVybiBKU09OUmVzcG9uc2Uoc3Rh"
    "dHVzX2NvZGU9NDI5LCBjb250ZW50PXsiZXJyb3IiOiAiUmF0ZSBsaW1pdCBleGNlZWRlZCJ9KQoK"
    "IyBbU0VDVVJJVFldIENPUlMg7KCc7ZWcCmlmIEFMTE9XRURfT1JJR0lOUzoKICAgIGFwcC5hZGRf"
    "bWlkZGxld2FyZShDT1JTTWlkZGxld2FyZSwgYWxsb3dfb3JpZ2lucz1BTExPV0VEX09SSUdJTlMs"
    "CiAgICAgICAgYWxsb3dfbWV0aG9kcz1bIkdFVCIsIlBPU1QiXSwgYWxsb3dfaGVhZGVycz1bIkF1"
    "dGhvcml6YXRpb24iLCJDb250ZW50LVR5cGUiXSkKZWxzZToKICAgIGFwcC5hZGRfbWlkZGxld2Fy"
    "ZShDT1JTTWlkZGxld2FyZSwgYWxsb3dfb3JpZ2lucz1bIioiXSwKICAgICAgICBhbGxvd19tZXRo"
    "b2RzPVsiR0VUIiwiUE9TVCJdLCBhbGxvd19oZWFkZXJzPVsiKiJdKQoKIyBbU0VDVVJJVFldIOuz"
    "tOyViCDtl6TrjZQg66+465Ok7Juo7Ja0CkBhcHAubWlkZGxld2FyZSgiaHR0cCIpCmFzeW5jIGRl"
    "ZiBzZWN1cml0eV9oZWFkZXJzKHJlcXVlc3Q6IFJlcXVlc3QsIGNhbGxfbmV4dCk6CiAgICAjIFtT"
    "RUNVUklUWV0g7JqU7LKtIOuzuOusuCDtgazquLAg7KCc7ZWcICgxMEtCKQogICAgY29udGVudF9s"
    "ZW5ndGggPSByZXF1ZXN0LmhlYWRlcnMuZ2V0KCJjb250ZW50LWxlbmd0aCIsICIwIikKICAgIGlm"
    "IGludChjb250ZW50X2xlbmd0aCkgPiAxMDI0MDoKICAgICAgICByZXR1cm4gSlNPTlJlc3BvbnNl"
    "KHN0YXR1c19jb2RlPTQxMywgY29udGVudD17ImVycm9yIjogIlJlcXVlc3QgdG9vIGxhcmdlIn0p"
    "CiAgICByZXNwb25zZSA9IGF3YWl0IGNhbGxfbmV4dChyZXF1ZXN0KQogICAgcmVzcG9uc2UuaGVh"
    "ZGVyc1siWC1Db250ZW50LVR5cGUtT3B0aW9ucyJdID0gIm5vc25pZmYiCiAgICByZXNwb25zZS5o"
    "ZWFkZXJzWyJYLUZyYW1lLU9wdGlvbnMiXSA9ICJERU5ZIgogICAgcmVzcG9uc2UuaGVhZGVyc1si"
    "WC1YU1MtUHJvdGVjdGlvbiJdID0gIjE7IG1vZGU9YmxvY2siCiAgICByZXNwb25zZS5oZWFkZXJz"
    "WyJSZWZlcnJlci1Qb2xpY3kiXSA9ICJzdHJpY3Qtb3JpZ2luLXdoZW4tY3Jvc3Mtb3JpZ2luIgog"
    "ICAgcmVzcG9uc2UuaGVhZGVyc1siUGVybWlzc2lvbnMtUG9saWN5Il0gPSAiY2FtZXJhPSgpLCBt"
    "aWNyb3Bob25lPSgpLCBnZW9sb2NhdGlvbj0oKSIKICAgIHJlc3BvbnNlLmhlYWRlcnNbIkNvbnRl"
    "bnQtU2VjdXJpdHktUG9saWN5Il0gPSAiZGVmYXVsdC1zcmMgJ25vbmUnOyBmcmFtZS1hbmNlc3Rv"
    "cnMgJ25vbmUnIgogICAgcmVzcG9uc2UuaGVhZGVyc1siQ2FjaGUtQ29udHJvbCJdID0gIm5vLXN0"
    "b3JlLCBuby1jYWNoZSwgbXVzdC1yZXZhbGlkYXRlIgogICAgcmVzcG9uc2UuaGVhZGVyc1siUHJh"
    "Z21hIl0gPSAibm8tY2FjaGUiCiAgICByZXNwb25zZS5oZWFkZXJzWyJYLVJlcXVlc3QtSUQiXSA9"
    "IHNlY3JldHMudG9rZW5faGV4KDgpCiAgICByZXR1cm4gcmVzcG9uc2UKCiMg4pSA4pSAIOuqqOuN"
    "uCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIAKY2xhc3MgTXVsdGlUYWJSZXF1ZXN0KEJhc2VNb2RlbCk6CiAgICB0YXNrOiBzdHIgPSBGaWVs"
    "ZCguLi4sIG1pbl9sZW5ndGg9MSwgbWF4X2xlbmd0aD0yMDAwLCBkZXNjcmlwdGlvbj0i67mE6rWQ"
    "L+u2hOyEne2VoCDsnpHsl4UiKQogICAgdXJsczogbGlzdFtzdHJdID0gRmllbGQoZGVmYXVsdD1b"
    "XSwgbWF4X2xlbmd0aD01LCBkZXNjcmlwdGlvbj0i67Cp66y47ZWgIFVSTCDrqqnroZ0gKOy1nOuM"
    "gCA16rCcKSIpCiAgICBtYXhfc3RlcHNfcGVyX3RhYjogaW50ID0gRmllbGQoZGVmYXVsdD04LCBn"
    "ZT0xLCBsZT0xNSkKICAgIHByb3ZpZGVyOiBPcHRpb25hbFtzdHJdID0gTm9uZQogICAgYXBpX2tl"
    "eTogT3B0aW9uYWxbc3RyXSA9IE5vbmUKICAgIG1vZGVsOiBPcHRpb25hbFtzdHJdID0gTm9uZQoK"
    "Y2xhc3MgQnJvd3NlUmVxdWVzdChCYXNlTW9kZWwpOgogICAgdGFzazogc3RyID0gRmllbGQoLi4u"
    "LCBtaW5fbGVuZ3RoPTEsIG1heF9sZW5ndGg9MjAwMCkKICAgIHVybDogT3B0aW9uYWxbc3RyXSA9"
    "IEZpZWxkKE5vbmUsIG1heF9sZW5ndGg9NTAwKQogICAgbWF4X3N0ZXBzOiBPcHRpb25hbFtpbnRd"
    "ID0gRmllbGQoTm9uZSwgZ2U9MSwgbGU9MzApCiAgICB1c2VfdmlzaW9uOiBPcHRpb25hbFtib29s"
    "XSA9IE5vbmUKICAgIHByb3ZpZGVyOiBPcHRpb25hbFtzdHJdID0gRmllbGQoTm9uZSwgZGVzY3Jp"
    "cHRpb249IkxMTSBwcm92aWRlcjogZ3JvcS9vcGVuYWkvYW50aHJvcGljL2dvb2dsZSIpCiAgICBh"
    "cGlfa2V5OiBPcHRpb25hbFtzdHJdID0gRmllbGQoTm9uZSwgZGVzY3JpcHRpb249Ik92ZXJyaWRl"
    "IEFQSSBrZXkiKQogICAgbW9kZWw6IE9wdGlvbmFsW3N0cl0gPSBGaWVsZChOb25lLCBkZXNjcmlw"
    "dGlvbj0iT3ZlcnJpZGUgbW9kZWwgbmFtZSIpCiAgICBidWRnZXRfdXNkOiBPcHRpb25hbFtmbG9h"
    "dF0gPSBGaWVsZChOb25lLCBnZT0wLCBsZT0xMCwKICAgICAgICBkZXNjcmlwdGlvbj0iTXVsdGkt"
    "QWdlbnQgTExNIOu5hOyaqSDsg4HtlZwgKFVTRCkuIDAg65iQ64qUIOuvuOyngOygleydtOuptCDr"
    "rLTsoJztlZwuIikKCiAgICBAZmllbGRfdmFsaWRhdG9yKCJ1cmwiKQogICAgQGNsYXNzbWV0aG9k"
    "CiAgICBkZWYgY2hlY2tfdXJsKGNscywgdik6CiAgICAgICAgaWYgdiBhbmQgbm90IHZhbGlkYXRl"
    "X3VybCh2KToKICAgICAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiVVJMIG5vdCBhbGxvd2VkIChi"
    "bG9ja2VkIHNjaGVtZSBvciBpbnRlcm5hbCBuZXR3b3JrKSIpCiAgICAgICAgcmV0dXJuIHYKCiAg"
    "ICBAZmllbGRfdmFsaWRhdG9yKCJ0YXNrIikKICAgIEBjbGFzc21ldGhvZAogICAgZGVmIGNoZWNr"
    "X3Rhc2soY2xzLCB2KToKICAgICAgICByZXR1cm4gc2FuaXRpemVfdGFzayh2KQoKY2xhc3MgQnJv"
    "d3NlUmVzcG9uc2UoQmFzZU1vZGVsKToKICAgIHN1Y2Nlc3M6IGJvb2wKICAgIHN1bW1hcnk6IE9w"
    "dGlvbmFsW3N0cl0gPSBOb25lCiAgICBzdW1tYXJ5X3BsYWluOiBPcHRpb25hbFtzdHJdID0gTm9u"
    "ZQogICAgZXJyb3I6IE9wdGlvbmFsW3N0cl0gPSBOb25lCiAgICBzdGVwc190YWtlbjogaW50ID0g"
    "MAogICAgZWxhcHNlZF9zZWM6IGZsb2F0ID0gMC4wCiAgICB0aW1lc3RhbXA6IHN0ciA9ICIiCgoj"
    "IOKUgOKUgCDruIzrnbzsmrDsoIAg7Iuk7ZaJIO2XrO2NvCAo7YOA7J6E7JWE7JuDIO2PrO2VqCkg"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACmFzeW5jIGRlZiBfcnVuX2FnZW50KHRhc2s6IHN0ciwg"
    "c3RlcHM6IGludCwgdmlzaW9uOiBib29sLCBvdmVycmlkZV9sbG09Tm9uZSkgLT4gZGljdDoKICAg"
    "IHNlc3Npb24gPSBOb25lCiAgICB0MCA9IHRpbWUudGltZSgpCiAgICB0cnk6CiAgICAgICAgc2Vz"
    "c2lvbiA9IEJyb3dzZXJTZXNzaW9uKGJyb3dzZXJfcHJvZmlsZT1Ccm93c2VyUHJvZmlsZSgKICAg"
    "ICAgICAgICAgaGVhZGxlc3M9VHJ1ZSwgZGlzYWJsZV9zZWN1cml0eT1GYWxzZSwKICAgICAgICAg"
    "ICAgdmlld3BvcnQ9eyJ3aWR0aCI6IDEyODAsICJoZWlnaHQiOiA3MjB9KSkKCiAgICAgICAgYWN0"
    "aXZlX2xsbSA9IG92ZXJyaWRlX2xsbSBvciBsbG0KICAgICAgICBhZ2VudCA9IEFnZW50KHRhc2s9"
    "dGFzaywgbGxtPWFjdGl2ZV9sbG0sIGJyb3dzZXJfc2Vzc2lvbj1zZXNzaW9uLAogICAgICAgICAg"
    "ICAgICAgICAgICAgdXNlX3Zpc2lvbj12aXNpb24sIG1heF9hY3Rpb25zX3Blcl9zdGVwPTUpCgog"
    "ICAgICAgICMgW0FOVEktTE9PUF0gYXN5bmNpby53YWl0X2ZvcuuhnCDsoITssrQg7YOA7J6E7JWE"
    "7JuDIOyggeyaqQogICAgICAgIHJlc3VsdCA9IGF3YWl0IGFzeW5jaW8ud2FpdF9mb3IoCiAgICAg"
    "ICAgICAgIGFnZW50LnJ1bihtYXhfc3RlcHM9c3RlcHMpLAogICAgICAgICAgICB0aW1lb3V0PVRB"
    "U0tfVElNRU9VVAogICAgICAgICkKCiAgICAgICAgZmluYWwgPSByZXN1bHQuZmluYWxfcmVzdWx0"
    "KCkgaWYgcmVzdWx0IGVsc2UgImNvbXBsZXRlZCIKICAgICAgICBoaXN0b3J5ID0gcmVzdWx0Lmhp"
    "c3RvcnkgaWYgcmVzdWx0IGVsc2UgW10KICAgICAgICBuID0gbGVuKGhpc3RvcnkpIGlmIGhpc3Rv"
    "cnkgZWxzZSAwCiAgICAgICAgZWxhcHNlZCA9IHJvdW5kKHRpbWUudGltZSgpIC0gdDAsIDIpCgog"
    "ICAgICAgIHJldHVybiB7InN1Y2Nlc3MiOiBUcnVlLCAic3VtbWFyeSI6IGZpbmFsLCAic3VtbWFy"
    "eV9wbGFpbiI6IGZpbmFsLAogICAgICAgICAgICAgICAgInN0ZXBzX3Rha2VuIjogbiwgImVsYXBz"
    "ZWRfc2VjIjogZWxhcHNlZH0KCiAgICBleGNlcHQgYXN5bmNpby5UaW1lb3V0RXJyb3I6CiAgICAg"
    "ICAgZWxhcHNlZCA9IHJvdW5kKHRpbWUudGltZSgpIC0gdDAsIDIpCiAgICAgICAgYXVkaXRfbG9n"
    "Z2VyLmluZm8oZiJUSU1FT1VUfHtlbGFwc2VkfXN8e3Rhc2tbOjgwXX0iKQogICAgICAgIHJldHVy"
    "biB7InN1Y2Nlc3MiOiBGYWxzZSwKICAgICAgICAgICAgICAgICJlcnJvciI6IGYiVGFzayB0aW1l"
    "ZCBvdXQgYWZ0ZXIge1RBU0tfVElNRU9VVH1zICh7ZWxhcHNlZH1zIGVsYXBzZWQpIiwKICAgICAg"
    "ICAgICAgICAgICJlbGFwc2VkX3NlYyI6IGVsYXBzZWR9CgogICAgZXhjZXB0IEV4Y2VwdGlvbiBh"
    "cyBlOgogICAgICAgIGVsYXBzZWQgPSByb3VuZCh0aW1lLnRpbWUoKSAtIHQwLCAyKQogICAgICAg"
    "IHJldHVybiB7InN1Y2Nlc3MiOiBGYWxzZSwgImVycm9yIjogc3RyKGUpLCAiZWxhcHNlZF9zZWMi"
    "OiBlbGFwc2VkfQoKICAgIGZpbmFsbHk6CiAgICAgICAgaWYgc2Vzc2lvbjoKICAgICAgICAgICAg"
    "dHJ5OiBhd2FpdCBhc3luY2lvLndhaXRfZm9yKHNlc3Npb24uY2xvc2UoKSwgdGltZW91dD01KQog"
    "ICAgICAgICAgICBleGNlcHQ6IHBhc3MKCgojIOKUgOKUgCDrqZTrqqjrpqwv7ZWZ7Iq1IOyLnOyK"
    "pO2FnCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIAKaW1wb3J0IGpzb24gYXMgX2pzb24KZnJvbSBwYXRobGliIGlt"
    "cG9ydCBQYXRoIGFzIF9QYXRoCgpNRU1PUllfRklMRSA9IF9QYXRoKCIvYXBwL2RhdGEvdXNlcl9t"
    "ZW1vcnkuanNvbiIpCkFMTE9XRURfRklMRV9FWFQgPSB7Ii50eHQiLCIubWQiLCIuY3N2IiwiLmpz"
    "b24iLCIucGRmIiwiLnhsc3giLCIueGxzIiwiLmRvY3giLCIuaHRtbCIsIi54bWwiLCIubG9nIiwi"
    "LnB5IiwiLnNoIn0KVVNFUl9GSUxFU19ESVIgPSBfUGF0aCgiL2FwcC9kYXRhL3VzZXJfZmlsZXMi"
    "KQoKZGVmIF9sb2FkX21lbW9yeSgpIC0+IGRpY3Q6CiAgICB0cnk6CiAgICAgICAgaWYgTUVNT1JZ"
    "X0ZJTEUuZXhpc3RzKCk6CiAgICAgICAgICAgIHJldHVybiBfanNvbi5sb2FkcyhNRU1PUllfRklM"
    "RS5yZWFkX3RleHQoInV0Zi04IikpCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHBhc3MK"
    "ICAgIHJldHVybiB7ImxvY2F0aW9uIjoiIiwiaW50ZXJlc3RzIjpbXSwicHJlZmVyZW5jZXMiOnt9"
    "LCJmYWN0cyI6W10sInBhc3RfcXVlcmllcyI6W119CgpkZWYgX3NhdmVfbWVtb3J5KG1lbTogZGlj"
    "dCk6CiAgICB0cnk6CiAgICAgICAgTUVNT1JZX0ZJTEUucGFyZW50Lm1rZGlyKHBhcmVudHM9VHJ1"
    "ZSwgZXhpc3Rfb2s9VHJ1ZSkKICAgICAgICBNRU1PUllfRklMRS53cml0ZV90ZXh0KF9qc29uLmR1"
    "bXBzKG1lbSwgZW5zdXJlX2FzY2lpPUZhbHNlLCBpbmRlbnQ9MiksICJ1dGYtOCIpCiAgICBleGNl"
    "cHQgRXhjZXB0aW9uIGFzIGU6CiAgICAgICAgbG9nZ2VyLmVycm9yKGYiTWVtb3J5IHNhdmUgZmFp"
    "bGVkOiB7ZX0iKQoKZGVmIF91cGRhdGVfbWVtb3J5X2Zyb21fdGFzayh0YXNrOiBzdHIsIHJlc3Vs"
    "dDogc3RyKToKICAgICIiIuyekeyXhSDquLDroZ3sl5DshJwg7J6Q64+Z7Jy866GcIOyCrOyaqeye"
    "kCDsoJXrs7Qg7ZWZ7Iq1IiIiCiAgICBtZW0gPSBfbG9hZF9tZW1vcnkoKQogICAgIyDstZzqt7wg"
    "7L+866asIOyggOyepSAo7LWc64yAIDUw6rCcKQogICAgbWVtWyJwYXN0X3F1ZXJpZXMiXSA9IG1l"
    "bS5nZXQoInBhc3RfcXVlcmllcyIsIFtdKVstNDk6XSArIFsKICAgICAgICB7InRhc2siOiB0YXNr"
    "WzoyMDBdLCAidGltZSI6IGRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpfQogICAgXQogICAgIyDs"
    "nITsuZgg7J6Q64+ZIOqwkOyngAogICAgaW1wb3J0IHJlIGFzIF9yZTIKICAgIGxvY19tYXRjaCA9"
    "IF9yZTIuc2VhcmNoKHIiKOyEnOyauHzrtoDsgrB864yA6rWsfOyduOyynHzqtJHso7x864yA7KCE"
    "fOyauOyCsHzshLjsooV87KCc7KO8fOyImOybkHzshLHrgqh86rOg7JaRKSIsIHRhc2spCiAgICBp"
    "ZiBsb2NfbWF0Y2ggYW5kIG5vdCBtZW0uZ2V0KCJsb2NhdGlvbiIpOgogICAgICAgIG1lbVsibG9j"
    "YXRpb24iXSA9IGxvY19tYXRjaC5ncm91cCgxKQogICAgIyDqtIDsi6zsgqwg7J6Q64+ZIOqwkOyn"
    "gAogICAgaW50ZXJlc3Rfa2V5d29yZHMgPSB7IuyjvOqwgCI6IuyjvOyLnSIsIu2ZmOycqCI6Iuq4"
    "iOyctSIsIuuCoOyUqCI6IuuCoOyUqCIsIuuJtOyKpCI6IuuJtOyKpCIsCiAgICAgICAgICAgICAg"
    "ICAgICAgICAgICAi6rCA6rKpIjoi7Ie87ZWRIiwi7ZWt6rO1Ijoi7Jes7ZaJIiwi66eb7KeRIjoi"
    "7J2M7IudIiwi67aA64+Z7IKwIjoi67aA64+Z7IKwIn0KICAgIGZvciBrdywgaW50ZXJlc3QgaW4g"
    "aW50ZXJlc3Rfa2V5d29yZHMuaXRlbXMoKToKICAgICAgICBpZiBrdyBpbiB0YXNrIGFuZCBpbnRl"
    "cmVzdCBub3QgaW4gbWVtLmdldCgiaW50ZXJlc3RzIixbXSk6CiAgICAgICAgICAgIG1lbS5zZXRk"
    "ZWZhdWx0KCJpbnRlcmVzdHMiLFtdKS5hcHBlbmQoaW50ZXJlc3QpCiAgICAgICAgICAgIG1lbVsi"
    "aW50ZXJlc3RzIl0gPSBtZW1bImludGVyZXN0cyJdWy0yMDpdCiAgICBfc2F2ZV9tZW1vcnkobWVt"
    "KQoKZGVmIF9nZXRfbWVtb3J5X2NvbnRleHQoKSAtPiBzdHI6CiAgICAiIiJMTE0g7ZSE66Gs7ZSE"
    "7Yq47JeQIOyjvOyehe2VoCDrqZTrqqjrpqwg7Luo7YWN7Iqk7Yq4IiIiCiAgICBtZW0gPSBfbG9h"
    "ZF9tZW1vcnkoKQogICAgcGFydHMgPSBbXQogICAgaWYgbWVtLmdldCgibG9jYXRpb24iKToKICAg"
    "ICAgICBwYXJ0cy5hcHBlbmQoZiJVc2VyIGxvY2F0aW9uOiB7bWVtWydsb2NhdGlvbiddfSIpCiAg"
    "ICBpZiBtZW0uZ2V0KCJpbnRlcmVzdHMiKToKICAgICAgICBwYXJ0cy5hcHBlbmQoZiJVc2VyIGlu"
    "dGVyZXN0czogeycsICcuam9pbihtZW1bJ2ludGVyZXN0cyddWzoxMF0pfSIpCiAgICBpZiBtZW0u"
    "Z2V0KCJwcmVmZXJlbmNlcyIpOgogICAgICAgIHBhcnRzLmFwcGVuZChmIlByZWZlcmVuY2VzOiB7"
    "X2pzb24uZHVtcHMobWVtWydwcmVmZXJlbmNlcyddLCBlbnN1cmVfYXNjaWk9RmFsc2UpfSIpCiAg"
    "ICBpZiBtZW0uZ2V0KCJmYWN0cyIpOgogICAgICAgIHBhcnRzLmFwcGVuZChmIktub3duIGZhY3Rz"
    "OiB7JzsgJy5qb2luKG1lbVsnZmFjdHMnXVstNTpdKX0iKQogICAgcmV0dXJuICJcbiIuam9pbihw"
    "YXJ0cykgaWYgcGFydHMgZWxzZSAiIgoKIyDilIDilIAg66Gc7LusIO2MjOydvCDsoJHqt7wg7Iuc"
    "7Iqk7YWcIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgApkZWYgX3NhZmVfcGF0aChmaWxlbmFtZTogc3RyKSAtPiBfUGF0aDoKICAg"
    "ICIiIuqyveuhnCDtg4jstpwg67Cp7KeAIiIiCiAgICBjbGVhbiA9IF9QYXRoKGZpbGVuYW1lKS5u"
    "YW1lICAjIOuUlOugie2GoOumrCDtg5Dsg4kg7LCo64uoCiAgICBpZiAiLi4iIGluIHN0cihmaWxl"
    "bmFtZSkgb3IgIi8iIGluIGZpbGVuYW1lIG9yICJcXCIgaW4gZmlsZW5hbWU6CiAgICAgICAgcmFp"
    "c2UgVmFsdWVFcnJvcigiSW52YWxpZCBmaWxlbmFtZSIpCiAgICBwYXRoID0gVVNFUl9GSUxFU19E"
    "SVIgLyBjbGVhbgogICAgaWYgbm90IHN0cihwYXRoLnJlc29sdmUoKSkuc3RhcnRzd2l0aChzdHIo"
    "VVNFUl9GSUxFU19ESVIucmVzb2x2ZSgpKSk6CiAgICAgICAgcmFpc2UgVmFsdWVFcnJvcigiUGF0"
    "aCB0cmF2ZXJzYWwgYmxvY2tlZCIpCiAgICBpZiBwYXRoLnN1ZmZpeC5sb3dlcigpIG5vdCBpbiBB"
    "TExPV0VEX0ZJTEVfRVhUOgogICAgICAgIHJhaXNlIFZhbHVlRXJyb3IoZiJFeHRlbnNpb24gbm90"
    "IGFsbG93ZWQ6IHtwYXRoLnN1ZmZpeH0iKQogICAgcmV0dXJuIHBhdGgKCiMg4pSA4pSAIOyXlOuT"
    "nO2PrOyduO2KuCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDi"
    "lIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKQGFwcC5n"
    "ZXQoIi9oZWFsdGgiKQpkZWYgaGVhbHRoKCk6CiAgICBtdWx0aV9vayA9IEZhbHNlCiAgICB0cnk6"
    "CiAgICAgICAgZnJvbSBtdWx0aV9hZ2VudC5ncmFwaCBpbXBvcnQgYnVpbGRfZ3JhcGgKICAgICAg"
    "ICBtdWx0aV9vayA9IFRydWUKICAgIGV4Y2VwdCBFeGNlcHRpb246IHBhc3MKICAgIHJldHVybiB7"
    "InN0YXR1cyI6ICJoZWFsdGh5IiBpZiBsbG0gZWxzZSAibm9fYXBpX2tleSIsCiAgICAgICAgICAg"
    "ICJtb2RlbCI6IEdST1FfTU9ERUwsICJ2ZXJzaW9uIjogIjYuMS4wIiwKICAgICAgICAgICAgImVu"
    "Z2luZSI6ICJicm93c2VyLXVzZSIsCiAgICAgICAgICAgICJtdWx0aV9hZ2VudCI6IG11bHRpX29r"
    "LAogICAgICAgICAgICAidGltZW91dHMiOiB7InRhc2siOiBUQVNLX1RJTUVPVVQsICJtdWx0aSI6"
    "IE1VTFRJX1RJTUVPVVR9LAogICAgICAgICAgICAiY29uY3VycmVudCI6IGYie19hY3RpdmVfdGFz"
    "a3N9L3tNQVhfQ09OQ1VSUkVOVH0iLAogICAgICAgICAgICAibWVtb3J5IjogTUVNT1JZX0ZJTEUu"
    "ZXhpc3RzKCksCiAgICAgICAgICAgICJ1c2VyX2ZpbGVzIjogVVNFUl9GSUxFU19ESVIuZXhpc3Rz"
    "KCl9CgpAYXBwLmdldCgiL2hlYWx0aC9tdWx0aSIpCmRlZiBoZWFsdGhfbXVsdGkoKToKICAgIHRy"
    "eToKICAgICAgICBmcm9tIG11bHRpX2FnZW50LmdyYXBoIGltcG9ydCBidWlsZF9ncmFwaAogICAg"
    "ICAgIHJldHVybiB7Im11bHRpX2FnZW50X2VuYWJsZWQiOiBUcnVlfQogICAgZXhjZXB0IEV4Y2Vw"
    "dGlvbiBhcyBlOgogICAgICAgIHJldHVybiB7Im11bHRpX2FnZW50X2VuYWJsZWQiOiBGYWxzZSwg"
    "ImVycm9yIjogc3RyKGUpfQoKQGFwcC5wb3N0KCIvYnJvd3NlIiwgcmVzcG9uc2VfbW9kZWw9QnJv"
    "d3NlUmVzcG9uc2UpCkBsaW1pdGVyLmxpbWl0KCIxMC9taW51dGUiKQphc3luYyBkZWYgYnJvd3Nl"
    "KHJlcXVlc3Q6IFJlcXVlc3QsIGJvZHk6IEJyb3dzZVJlcXVlc3QsCiAgICAgICAgICAgICAgICAg"
    "Xz1EZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAgICBpZiBub3QgbGxtOgogICAgICAgIHJhaXNl"
    "IEhUVFBFeGNlcHRpb24oNTAwLCAiTm8gTExNIGNvbmZpZ3VyZWQg4oCUIHNldCBHUk9RX0FQSV9L"
    "RVksIE9QRU5BSV9BUElfS0VZLCBBTlRIUk9QSUNfQVBJX0tFWSwgb3IgR09PR0xFX0FQSV9LRVki"
    "KQoKICAgICMg66mU66qo66asIOy7qO2FjeyKpO2KuCDso7zsnoUKICAgIG1lbV9jdHggPSBfZ2V0"
    "X21lbW9yeV9jb250ZXh0KCkKICAgIHJhd190YXNrID0gYm9keS50YXNrCiAgICBpZiBtZW1fY3R4"
    "OgogICAgICAgIGZ1bGxfdGFzayA9IGYiW1VzZXIgY29udGV4dDoge21lbV9jdHh9XVxue2JvZHku"
    "dGFza30iCiAgICBlbHNlOgogICAgICAgIGZ1bGxfdGFzayA9IGJvZHkudGFzawogICAgZnVsbF90"
    "YXNrID0gYXBwbHlfbmF2ZXJfcHJpb3JpdHkoZnVsbF90YXNrKQogICAgaWYgYm9keS51cmw6CiAg"
    "ICAgICAgZnVsbF90YXNrID0gZiJHbyB0byB7Ym9keS51cmx9IGZpcnN0LCB0aGVuIHtib2R5LnRh"
    "c2t9IgoKICAgIHN0ZXBzID0gYm9keS5tYXhfc3RlcHMgb3IgTUFYX1NURVBTCiAgICB2aXNpb24g"
    "PSBib2R5LnVzZV92aXNpb24gaWYgYm9keS51c2VfdmlzaW9uIGlzIG5vdCBOb25lIGVsc2UgVVNF"
    "X1ZJU0lPTgoKICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiQlJPV1NFfHtyZXF1ZXN0LmNsaWVudC5o"
    "b3N0fXx7ZnVsbF90YXNrWzoxMDBdfSIpCgogICAgIyDsmpTssq3rs4Qg7ZSE66Gc67CU7J20642U"
    "IOyYpOuyhOudvOydtOuTnAogICAgb3ZlcnJpZGVfbGxtID0gTm9uZQogICAgaWYgYm9keS5wcm92"
    "aWRlciBvciBib2R5LmFwaV9rZXk6CiAgICAgICAgdHJ5OgogICAgICAgICAgICBvdmVycmlkZV9s"
    "bG0gPSBjcmVhdGVfbGxtKAogICAgICAgICAgICAgICAgcHJvdmlkZXI9Ym9keS5wcm92aWRlciwK"
    "ICAgICAgICAgICAgICAgIGFwaV9rZXk9Ym9keS5hcGlfa2V5LAogICAgICAgICAgICAgICAgbW9k"
    "ZWw9Ym9keS5tb2RlbAogICAgICAgICAgICApCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBl"
    "OgogICAgICAgICAgICByZXR1cm4gQnJvd3NlUmVzcG9uc2Uoc3VjY2Vzcz1GYWxzZSwgZXJyb3I9"
    "ZiJMTE0gb3ZlcnJpZGUgZmFpbGVkOiB7ZX0iLAogICAgICAgICAgICAgICAgICAgICAgICAgICAg"
    "ICAgICAgdGltZXN0YW1wPWRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpKQoKICAgIGFzeW5jIHdp"
    "dGggdGFza19zbG90KCk6CiAgICAgICAgcmVzdWx0ID0gYXdhaXQgX3J1bl9hZ2VudChmdWxsX3Rh"
    "c2ssIHN0ZXBzLCB2aXNpb24sIG92ZXJyaWRlX2xsbSkKCiAgICAgICAgIyBbQU5USS1MT09QXSBT"
    "ZWxmLUhlYWxpbmc6IO2DgOyehOyVhOybgy/rhKTruYTqsozsnbTshZgg7JeQ65+sIOyLnCAx7ZqM"
    "66eMIOyerOyLnOuPhAogICAgICAgIGlmIG5vdCByZXN1bHRbInN1Y2Nlc3MiXToKICAgICAgICAg"
    "ICAgZXJyID0gcmVzdWx0LmdldCgiZXJyb3IiLCAiIikubG93ZXIoKQogICAgICAgICAgICByZXRy"
    "eWFibGUgPSBhbnkoayBpbiBlcnIgZm9yIGsgaW4KICAgICAgICAgICAgICAgIFsidGltZW91dCIs"
    "ICJuYXZpZ2F0aW9uIiwgInRhcmdldCBjbG9zZWQiLCAic2Vzc2lvbiBjbG9zZWQiXSkKICAgICAg"
    "ICAgICAgaWYgcmV0cnlhYmxlOgogICAgICAgICAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJS"
    "RVRSWXx7cmVxdWVzdC5jbGllbnQuaG9zdH0iKQogICAgICAgICAgICAgICAgcmV0cnkgPSBhd2Fp"
    "dCBfcnVuX2FnZW50KGZ1bGxfdGFzaywgbWF4KHN0ZXBzLy8yLCA1KSwgdmlzaW9uLCBvdmVycmlk"
    "ZV9sbG0pCiAgICAgICAgICAgICAgICBpZiByZXRyeVsic3VjY2VzcyJdOgogICAgICAgICAgICAg"
    "ICAgICAgIHJldHJ5WyJzdW1tYXJ5Il0gPSBmIltyZXRyeV0ge3JldHJ5LmdldCgnc3VtbWFyeScs"
    "JycpfSIKICAgICAgICAgICAgICAgICAgICByZXN1bHQgPSByZXRyeQoKICAgICAgICBpZiByZXN1"
    "bHRbInN1Y2Nlc3MiXToKICAgICAgICAgICAgX3VwZGF0ZV9tZW1vcnlfZnJvbV90YXNrKHJhd190"
    "YXNrLCByZXN1bHQuZ2V0KCJzdW1tYXJ5IiwiIikpCiAgICAgICAgICAgIGF1ZGl0X2xvZ2dlci5p"
    "bmZvKGYiQlJPV1NFX09LfHN0ZXBzPXtyZXN1bHRbJ3N0ZXBzX3Rha2VuJ119fHtyZXN1bHRbJ2Vs"
    "YXBzZWRfc2VjJ119cyIpCiAgICAgICAgZWxzZToKICAgICAgICAgICAgYXVkaXRfbG9nZ2VyLmlu"
    "Zm8oZiJCUk9XU0VfRkFJTHx7cmVzdWx0LmdldCgnZXJyb3InLCcnKVs6MjAwXX0iKQoKICAgICAg"
    "ICByZXR1cm4gQnJvd3NlUmVzcG9uc2UoCiAgICAgICAgICAgICoqcmVzdWx0LAogICAgICAgICAg"
    "ICB0aW1lc3RhbXA9ZGF0ZXRpbWUubm93KCkuaXNvZm9ybWF0KCkKICAgICAgICApCgoKIyDilIDi"
    "lIAg66mA7Yuw7YOtIOu4jOudvOyasOymiCDsl5Trk5ztj6zsnbjtirgg4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACkBhcHAucG9zdCgiL2Jyb3dzZS9t"
    "dWx0aXRhYiIpCkBsaW1pdGVyLmxpbWl0KCI1L21pbnV0ZSIpCmFzeW5jIGRlZiBicm93c2VfbXVs"
    "dGl0YWIocmVxdWVzdDogUmVxdWVzdCwgYm9keTogTXVsdGlUYWJSZXF1ZXN0LAogICAgICAgICAg"
    "ICAgICAgICAgICAgICAgIF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkpOgogICAgIiIi7Jes65+s"
    "IOyCrOydtO2KuOulvCDsiJzssKjsoIHsnLzroZwg67Cp66y47ZWY6rOgIOqysOqzvOulvCDsooXt"
    "lakg67mE6rWQIiIiCiAgICBpZiBub3QgbGxtOgogICAgICAgIHJhaXNlIEhUVFBFeGNlcHRpb24o"
    "NTAwLCAiTm8gTExNIGNvbmZpZ3VyZWQiKQoKICAgICMgR3JvcSDrrLTro4wg66qo6424IOqyveqz"
    "oAogICAgYWN0aXZlX2xsbSA9IGxsbQogICAgaWYgYm9keS5wcm92aWRlciBvciBib2R5LmFwaV9r"
    "ZXk6CiAgICAgICAgdHJ5OgogICAgICAgICAgICBhY3RpdmVfbGxtID0gY3JlYXRlX2xsbShwcm92"
    "aWRlcj1ib2R5LnByb3ZpZGVyLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
    "YXBpX2tleT1ib2R5LmFwaV9rZXksIG1vZGVsPWJvZHkubW9kZWwpCiAgICAgICAgZXhjZXB0IEV4"
    "Y2VwdGlvbiBhcyBlOgogICAgICAgICAgICByZXR1cm4geyJzdWNjZXNzIjogRmFsc2UsICJlcnJv"
    "ciI6IGYiTExNIG92ZXJyaWRlIGZhaWxlZDoge2V9In0KCiAgICBpZiBnZXRhdHRyKGFjdGl2ZV9s"
    "bG0sICJwcm92aWRlciIsICIiKSA9PSAiZ3JvcSI6CiAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8o"
    "Ik1VTFRJVEFCX1dBUk58Z3JvcV9wcm92aWRlcl91c2VkIikKCiAgICBhdWRpdF9sb2dnZXIuaW5m"
    "byhmIk1VTFRJVEFCfHtyZXF1ZXN0LmNsaWVudC5ob3N0fXx0YWJzPXtsZW4oYm9keS51cmxzKX18"
    "e2JvZHkudGFza1s6ODBdfSIpCgogICAgIyBVUkzsnbQg7JeG7Jy866m0IOyekeyXheyXkOyEnCDs"
    "npDrj5kg7LaU7LacIOyLnOuPhAogICAgdXJscyA9IGJvZHkudXJscwogICAgaWYgbm90IHVybHM6"
    "CiAgICAgICAgIyBMTE3sl5DqsowgVVJMIOy2lOy2nCDsmpTssq0KICAgICAgICBleHRyYWN0X3Rh"
    "c2sgPSBmIuuLpOydjCDsnpHsl4XsnYQg7IiY7ZaJ7ZWY6riwIOychO2VtCDrsKnrrLjtlaAg7Ju5"
    "7IKs7J207Yq4IFVSTOydhCDstZzrjIAgM+qwnCDstpTsspztlbTspJggKFVSTOunjCDtlZwg7KSE"
    "7JeQIO2VmOuCmOyUqSk6IHtib2R5LnRhc2t9IgogICAgICAgIHRyeToKICAgICAgICAgICAgZnJv"
    "bSBsYW5nY2hhaW5fY29yZS5tZXNzYWdlcyBpbXBvcnQgSHVtYW5NZXNzYWdlCiAgICAgICAgICAg"
    "IHJlc3AgPSBhd2FpdCBhY3RpdmVfbGxtLmFpbnZva2UoW0h1bWFuTWVzc2FnZShjb250ZW50PWV4"
    "dHJhY3RfdGFzayldKQogICAgICAgICAgICBpbXBvcnQgcmUgYXMgX3JlMwogICAgICAgICAgICBm"
    "b3VuZF91cmxzID0gX3JlMy5maW5kYWxsKHInaHR0cHM/Oi8vW15cczw+Il0rJywgcmVzcC5jb250"
    "ZW50KQogICAgICAgICAgICB1cmxzID0gZm91bmRfdXJsc1s6NV0KICAgICAgICBleGNlcHQgRXhj"
    "ZXB0aW9uOgogICAgICAgICAgICB1cmxzID0gW10KCiAgICBpZiBub3QgdXJsczoKICAgICAgICAj"
    "IOuEpOydtOuyhCDqsoDsg4nsnLzroZwg7Y+067CxCiAgICAgICAgdXJscyA9IFtmImh0dHBzOi8v"
    "c2VhcmNoLm5hdmVyLmNvbS9zZWFyY2gubmF2ZXI/cXVlcnk9e2JvZHkudGFza30iXQoKICAgICMg"
    "6rCBIO2DrShVUkwp67OE66GcIOyInOywqCDsi6TtlokKICAgIHRhYl9yZXN1bHRzID0gW10KICAg"
    "IGFzeW5jIHdpdGggdGFza19zbG90KCk6CiAgICAgICAgZm9yIGksIHVybCBpbiBlbnVtZXJhdGUo"
    "dXJsc1s6NV0pOgogICAgICAgICAgICB0YWJfdGFzayA9IGYiR28gdG8ge3VybH0gYW5kIGZpbmQg"
    "aW5mb3JtYXRpb24gYWJvdXQ6IHtib2R5LnRhc2t9LiBFeHRyYWN0IGtleSBkYXRhIGNvbmNpc2Vs"
    "eS4iCiAgICAgICAgICAgIHRyeToKICAgICAgICAgICAgICAgIHNlc3Npb24gPSBCcm93c2VyU2Vz"
    "c2lvbihicm93c2VyX3Byb2ZpbGU9QnJvd3NlclByb2ZpbGUoCiAgICAgICAgICAgICAgICAgICAg"
    "aGVhZGxlc3M9VHJ1ZSwgZGlzYWJsZV9zZWN1cml0eT1GYWxzZSwKICAgICAgICAgICAgICAgICAg"
    "ICB2aWV3cG9ydD17IndpZHRoIjogMTI4MCwgImhlaWdodCI6IDcyMH0pKQogICAgICAgICAgICAg"
    "ICAgYWdlbnQgPSBBZ2VudCh0YXNrPXRhYl90YXNrLCBsbG09YWN0aXZlX2xsbSwKICAgICAgICAg"
    "ICAgICAgICAgICAgICAgICAgICAgYnJvd3Nlcl9zZXNzaW9uPXNlc3Npb24sCiAgICAgICAgICAg"
    "ICAgICAgICAgICAgICAgICAgIHVzZV92aXNpb249RmFsc2UsIG1heF9hY3Rpb25zX3Blcl9zdGVw"
    "PTMpCiAgICAgICAgICAgICAgICByZXN1bHQgPSBhd2FpdCBhc3luY2lvLndhaXRfZm9yKAogICAg"
    "ICAgICAgICAgICAgICAgIGFnZW50LnJ1bihtYXhfc3RlcHM9Ym9keS5tYXhfc3RlcHNfcGVyX3Rh"
    "YiksCiAgICAgICAgICAgICAgICAgICAgdGltZW91dD1UQVNLX1RJTUVPVVQKICAgICAgICAgICAg"
    "ICAgICkKICAgICAgICAgICAgICAgIGZpbmFsID0gcmVzdWx0LmZpbmFsX3Jlc3VsdCgpIGlmIHJl"
    "c3VsdCBlbHNlICJb6rKw6rO87JeG7J2MXSIKICAgICAgICAgICAgICAgIHRhYl9yZXN1bHRzLmFw"
    "cGVuZCh7InRhYiI6IGkrMSwgInVybCI6IHVybCwgInJlc3VsdCI6IGZpbmFsWzozMDAwXSwgInN1"
    "Y2Nlc3MiOiBUcnVlfSkKICAgICAgICAgICAgZXhjZXB0IGFzeW5jaW8uVGltZW91dEVycm9yOgog"
    "ICAgICAgICAgICAgICAgdGFiX3Jlc3VsdHMuYXBwZW5kKHsidGFiIjogaSsxLCAidXJsIjogdXJs"
    "LCAicmVzdWx0IjogIlvtg4DsnoTslYTsm4NdIiwgInN1Y2Nlc3MiOiBGYWxzZX0pCiAgICAgICAg"
    "ICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgICAgIHRhYl9yZXN1bHRzLmFw"
    "cGVuZCh7InRhYiI6IGkrMSwgInVybCI6IHVybCwgInJlc3VsdCI6IGYiW+yYpOulmDoge3N0cihl"
    "KVs6MjAwXX1dIiwgInN1Y2Nlc3MiOiBGYWxzZX0pCiAgICAgICAgICAgIGZpbmFsbHk6CiAgICAg"
    "ICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICAgICAgaWYgJ3Nlc3Npb24nIGluIGxvY2Fs"
    "cygpOiBhd2FpdCBhc3luY2lvLndhaXRfZm9yKHNlc3Npb24uY2xvc2UoKSwgdGltZW91dD01KQog"
    "ICAgICAgICAgICAgICAgZXhjZXB0OiBwYXNzCgogICAgICAgICMg6rKw6rO8IOyihe2VqSDruYTq"
    "tZAKICAgICAgICBjb21wYXJlX3Byb21wdCA9IGYi64uk7J2M7J2AIOyXrOufrCDsgqzsnbTtirjs"
    "l5DshJwg7IiY7KeR7ZWcIOqysOqzvOyeheuLiOuLpC4gJ3tib2R5LnRhc2t9J+yXkCDrjIDtlbQg"
    "7KKF7ZWpIOu5hOq1kCDrtoTshJ3tlbTso7zshLjsmpQ6XG5cbiIKICAgICAgICBmb3IgdHIgaW4g"
    "dGFiX3Jlc3VsdHM6CiAgICAgICAgICAgIGNvbXBhcmVfcHJvbXB0ICs9IGYiW+2DrXt0clsndGFi"
    "J119IC0ge3RyWyd1cmwnXX1dXG57dHJbJ3Jlc3VsdCddfVxuXG4iCiAgICAgICAgY29tcGFyZV9w"
    "cm9tcHQgKz0gIuychCDqsrDqs7zrpbwg67mE6rWQIOu2hOyEne2VmOqzoCwg7ZW17Ius7J2EIO2V"
    "nOq1reyWtOuhnCDsoJXrpqztlbTso7zshLjsmpQuIgoKICAgICAgICB0cnk6CiAgICAgICAgICAg"
    "IGZyb20gbGFuZ2NoYWluX2NvcmUubWVzc2FnZXMgaW1wb3J0IEh1bWFuTWVzc2FnZQogICAgICAg"
    "ICAgICBzdW1tYXJ5ID0gYXdhaXQgYXN5bmNpby53YWl0X2ZvcigKICAgICAgICAgICAgICAgIGFj"
    "dGl2ZV9sbG0uYWludm9rZShbSHVtYW5NZXNzYWdlKGNvbnRlbnQ9Y29tcGFyZV9wcm9tcHQpXSks"
    "CiAgICAgICAgICAgICAgICB0aW1lb3V0PTYwCiAgICAgICAgICAgICkKICAgICAgICAgICAgZmlu"
    "YWxfc3VtbWFyeSA9IHN1bW1hcnkuY29udGVudAogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMg"
    "ZToKICAgICAgICAgICAgZmluYWxfc3VtbWFyeSA9ICJcbi0tLVxuIi5qb2luKFtmIlvtg617clsn"
    "dGFiJ119XSB7clsncmVzdWx0J11bOjUwMF19IiBmb3IgciBpbiB0YWJfcmVzdWx0c10pCgogICAg"
    "IyDrqZTrqqjrpqwg7JeF642w7J207Yq4CiAgICBfdXBkYXRlX21lbW9yeV9mcm9tX3Rhc2soYm9k"
    "eS50YXNrLCBmaW5hbF9zdW1tYXJ5Wzo1MDBdKQogICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJNVUxU"
    "SVRBQl9PS3x0YWJzPXtsZW4odGFiX3Jlc3VsdHMpfSIpCgogICAgcmV0dXJuIHsKICAgICAgICAi"
    "c3VjY2VzcyI6IFRydWUsCiAgICAgICAgInN1bW1hcnkiOiBmaW5hbF9zdW1tYXJ5LAogICAgICAg"
    "ICJ0YWJzIjogdGFiX3Jlc3VsdHMsCiAgICAgICAgInRhYl9jb3VudCI6IGxlbih0YWJfcmVzdWx0"
    "cyksCiAgICAgICAgInRpbWVzdGFtcCI6IGRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpCiAgICB9"
    "CgojIE11bHRpLUFnZW50IOyXlOuTnO2PrOyduO2KuApAYXBwLnBvc3QoIi9icm93c2UvbXVsdGki"
    "KQpAbGltaXRlci5saW1pdCgiNS9taW51dGUiKQphc3luYyBkZWYgYnJvd3NlX211bHRpKHJlcXVl"
    "c3Q6IFJlcXVlc3QsIGJvZHk6IEJyb3dzZVJlcXVlc3QsCiAgICAgICAgICAgICAgICAgICAgICAg"
    "Xz1EZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAgICB0cnk6CiAgICAgICAgZnJvbSBtdWx0aV9h"
    "Z2VudC5ncmFwaCBpbXBvcnQgYnVpbGRfZ3JhcGgKICAgICAgICBmcm9tIG11bHRpX2FnZW50Lmdy"
    "b3FfdXRpbHMgaW1wb3J0IFRva2VuVHJhY2tlcgogICAgZXhjZXB0IEltcG9ydEVycm9yOgogICAg"
    "ICAgIHJhaXNlIEhUVFBFeGNlcHRpb24oNTAxLCAiTXVsdGktQWdlbnQgbm90IGF2YWlsYWJsZSAo"
    "R1JPUV9BUElfS0VZIHJlcXVpcmVkKSIpCgogICAgIyBbQlVER0VUXSDsmpTssq3rs4Qg67mE7Jqp"
    "IOyDge2VnC4g66+47KeA7KCVIOyLnCBNVUxUSV9CVURHRVRfVVNEKOq4sOuzuCAwPeustOygnO2V"
    "nCkuCiAgICBfYnVkZ2V0ID0gYm9keS5idWRnZXRfdXNkIGlmIGJvZHkuYnVkZ2V0X3VzZCBpcyBu"
    "b3QgTm9uZSBlbHNlIE1VTFRJX0JVREdFVF9VU0QKICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiTVVM"
    "VEl8e3JlcXVlc3QuY2xpZW50Lmhvc3R9fGJ1ZGdldD0ke19idWRnZXQ6LjRmfXx7Ym9keS50YXNr"
    "WzoxMDBdfSIpCgogICAgYXN5bmMgd2l0aCB0YXNrX3Nsb3QoKToKICAgICAgICB0cnk6CiAgICAg"
    "ICAgICAgIGdyYXBoID0gYnVpbGRfZ3JhcGgoKQogICAgICAgICAgICBfdHJhY2tlciA9IFRva2Vu"
    "VHJhY2tlcihidWRnZXQ9X2J1ZGdldCkKICAgICAgICAgICAgc3RhdGUgPSB7Im9yaWdpbmFsX3Rh"
    "c2siOiBib2R5LnRhc2ssICJtZXNzYWdlcyI6IFtdLAogICAgICAgICAgICAgICAgICAgICAicmVz"
    "ZWFyY2hfcmVzdWx0cyI6IFtdLCAiYnJvd3Nlcl9yZXN1bHRzIjogW10sCiAgICAgICAgICAgICAg"
    "ICAgICAgICJpdGVyYXRpb24iOiAwLCAicm91dGVfaGlzdG9yeSI6IFtdLCAibmV4dCI6ICJzdXBl"
    "cnZpc29yIiwKICAgICAgICAgICAgICAgICAgICAgInRva2VuX3RyYWNrZXIiOiBfdHJhY2tlcn0K"
    "CiAgICAgICAgICAgICMgW0FOVEktTE9PUF0gTXVsdGktQWdlbnQg7KCE7LK0IO2DgOyehOyVhOyb"
    "gwogICAgICAgICAgICBmaW5hbCA9IGF3YWl0IGFzeW5jaW8ud2FpdF9mb3IoCiAgICAgICAgICAg"
    "ICAgICBncmFwaC5haW52b2tlKHN0YXRlKSwKICAgICAgICAgICAgICAgIHRpbWVvdXQ9TVVMVElf"
    "VElNRU9VVAogICAgICAgICAgICApCgogICAgICAgICAgICBtc2dzID0gZmluYWwuZ2V0KCJtZXNz"
    "YWdlcyIsIFtdKQogICAgICAgICAgICBsYXN0ID0gbXNnc1stMV0uY29udGVudCBpZiBtc2dzIGVs"
    "c2UgIm5vIHJlc3VsdCIKICAgICAgICAgICAgdG9rZW5faW5mbyA9IHt9CiAgICAgICAgICAgIGlm"
    "ICJ0b2tlbl90cmFja2VyIiBpbiBmaW5hbCBhbmQgZmluYWxbInRva2VuX3RyYWNrZXIiXToKICAg"
    "ICAgICAgICAgICAgIHRva2VuX2luZm8gPSBmaW5hbFsidG9rZW5fdHJhY2tlciJdLnN1bW1hcnkK"
    "ICAgICAgICAgICAgZWxpZiBfdHJhY2tlcjoKICAgICAgICAgICAgICAgIHRva2VuX2luZm8gPSBf"
    "dHJhY2tlci5zdW1tYXJ5CgogICAgICAgICAgICBhdWRpdF9sb2dnZXIuaW5mbyhmIk1VTFRJX09L"
    "fHRva2Vucz17dG9rZW5faW5mby5nZXQoJ3RvdGFsX3Rva2VucycsMCl9IikKICAgICAgICAgICAg"
    "cmV0dXJuIHsic3VjY2VzcyI6IFRydWUsICJyZXN1bHQiOiBsYXN0LAogICAgICAgICAgICAgICAg"
    "ICAgICJ0b2tlbl91c2FnZSI6IHRva2VuX2luZm8sCiAgICAgICAgICAgICAgICAgICAgInRpbWVz"
    "dGFtcCI6IGRhdGV0aW1lLm5vdygpLmlzb2Zvcm1hdCgpfQoKICAgICAgICBleGNlcHQgYXN5bmNp"
    "by5UaW1lb3V0RXJyb3I6CiAgICAgICAgICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiTVVMVElfVElN"
    "RU9VVHx7TVVMVElfVElNRU9VVH1zIikKICAgICAgICAgICAgcmV0dXJuIHsic3VjY2VzcyI6IEZh"
    "bHNlLAogICAgICAgICAgICAgICAgICAgICJlcnJvciI6IGYiTXVsdGktQWdlbnQgdGltZWQgb3V0"
    "IGFmdGVyIHtNVUxUSV9USU1FT1VUfXMiLAogICAgICAgICAgICAgICAgICAgICJ0aW1lc3RhbXAi"
    "OiBkYXRldGltZS5ub3coKS5pc29mb3JtYXQoKX0KICAgICAgICBleGNlcHQgUnVudGltZUVycm9y"
    "IGFzIGU6CiAgICAgICAgICAgIGlmICLsmIjsgrDstIjqs7wiIGluIHN0cihlKSBvciAiYnVkZ2V0"
    "IiBpbiBzdHIoZSkubG93ZXIoKToKICAgICAgICAgICAgICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYi"
    "TVVMVElfQlVER0VUX0VYQ0VFREVEfCR7X3RyYWNrZXIuY29zdDouNGZ9LyR7X2J1ZGdldDouNGZ9"
    "IikKICAgICAgICAgICAgICAgIHJldHVybiB7InN1Y2Nlc3MiOiBGYWxzZSwKICAgICAgICAgICAg"
    "ICAgICAgICAgICAgImVycm9yIjogZiLruYTsmqkg7IOB7ZWcKCR7X2J1ZGdldDouNGZ9KSDstIjq"
    "s7zroZwg7KSR64uo65CY7JeI7Iq164uI64ukLiIsCiAgICAgICAgICAgICAgICAgICAgICAgICJ0"
    "b2tlbl91c2FnZSI6IF90cmFja2VyLnN1bW1hcnksCiAgICAgICAgICAgICAgICAgICAgICAgICJ0"
    "aW1lc3RhbXAiOiBkYXRldGltZS5ub3coKS5pc29mb3JtYXQoKX0KICAgICAgICAgICAgYXVkaXRf"
    "bG9nZ2VyLmluZm8oZiJNVUxUSV9GQUlMfHtlfSIpCiAgICAgICAgICAgIHJldHVybiB7InN1Y2Nl"
    "c3MiOiBGYWxzZSwgImVycm9yIjogc3RyKGUpLAogICAgICAgICAgICAgICAgICAgICJ0aW1lc3Rh"
    "bXAiOiBkYXRldGltZS5ub3coKS5pc29mb3JtYXQoKX0KICAgICAgICBleGNlcHQgRXhjZXB0aW9u"
    "IGFzIGU6CiAgICAgICAgICAgIGF1ZGl0X2xvZ2dlci5pbmZvKGYiTVVMVElfRkFJTHx7ZX0iKQog"
    "ICAgICAgICAgICByZXR1cm4geyJzdWNjZXNzIjogRmFsc2UsICJlcnJvciI6IHN0cihlKSwKICAg"
    "ICAgICAgICAgICAgICAgICAidGltZXN0YW1wIjogZGF0ZXRpbWUubm93KCkuaXNvZm9ybWF0KCl9"
    "CgoKCiMg4pSA4pSAIOuplOuqqOumrCDsl5Trk5ztj6zsnbjtirgg4pSA4pSA4pSA4pSA4pSA4pSA"
    "4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA"
    "CkBhcHAuZ2V0KCIvbWVtb3J5IikKYXN5bmMgZGVmIGdldF9tZW1vcnkoXz1EZXBlbmRzKHZlcmlm"
    "eV9hcGlfa2V5KSk6CiAgICByZXR1cm4gX2xvYWRfbWVtb3J5KCkKCkBhcHAucG9zdCgiL21lbW9y"
    "eSIpCmFzeW5jIGRlZiB1cGRhdGVfbWVtb3J5KHJlcXVlc3Q6IFJlcXVlc3QsIF89RGVwZW5kcyh2"
    "ZXJpZnlfYXBpX2tleSkpOgogICAgYm9keSA9IGF3YWl0IHJlcXVlc3QuanNvbigpCiAgICBtZW0g"
    "PSBfbG9hZF9tZW1vcnkoKQogICAgaWYgImxvY2F0aW9uIiBpbiBib2R5OiBtZW1bImxvY2F0aW9u"
    "Il0gPSBzdHIoYm9keVsibG9jYXRpb24iXSlbOjUwXQogICAgaWYgImludGVyZXN0cyIgaW4gYm9k"
    "eTogbWVtWyJpbnRlcmVzdHMiXSA9IFtzdHIoaSlbOjMwXSBmb3IgaSBpbiBib2R5WyJpbnRlcmVz"
    "dHMiXVs6MjBdXQogICAgaWYgInByZWZlcmVuY2VzIiBpbiBib2R5OiBtZW1bInByZWZlcmVuY2Vz"
    "Il0udXBkYXRlKGJvZHlbInByZWZlcmVuY2VzIl0pCiAgICBpZiAiZmFjdHMiIGluIGJvZHk6IG1l"
    "bVsiZmFjdHMiXSA9IChtZW0uZ2V0KCJmYWN0cyIsW10pICsgW3N0cihmKVs6MjAwXSBmb3IgZiBp"
    "biBib2R5WyJmYWN0cyJdXSlbLTMwOl0KICAgIF9zYXZlX21lbW9yeShtZW0pCiAgICBhdWRpdF9s"
    "b2dnZXIuaW5mbyhmIk1FTU9SWV9VUERBVEV8e2xpc3QoYm9keS5rZXlzKCkpfSIpCiAgICByZXR1"
    "cm4geyJzdWNjZXNzIjogVHJ1ZSwgIm1lbW9yeSI6IG1lbX0KCkBhcHAuZGVsZXRlKCIvbWVtb3J5"
    "IikKYXN5bmMgZGVmIGNsZWFyX21lbW9yeShfPURlcGVuZHModmVyaWZ5X2FwaV9rZXkpKToKICAg"
    "IF9zYXZlX21lbW9yeSh7ImxvY2F0aW9uIjoiIiwiaW50ZXJlc3RzIjpbXSwicHJlZmVyZW5jZXMi"
    "Ont9LCJmYWN0cyI6W10sInBhc3RfcXVlcmllcyI6W119KQogICAgcmV0dXJuIHsic3VjY2VzcyI6"
    "IFRydWUsICJtZXNzYWdlIjogIk1lbW9yeSBjbGVhcmVkIn0KCiMg4pSA4pSAIO2MjOydvCDsoJHq"
    "t7wg7JeU65Oc7Y+s7J247Yq4IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKU"
    "gOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApAYXBwLmdldCgiL2ZpbGVzIikKYXN5bmMgZGVm"
    "IGxpc3RfZmlsZXMoXz1EZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAgICBpZiBub3QgVVNFUl9G"
    "SUxFU19ESVIuZXhpc3RzKCk6CiAgICAgICAgcmV0dXJuIHsiZmlsZXMiOiBbXSwgIm1lc3NhZ2Ui"
    "OiAiTm8gdXNlcl9maWxlcyBkaXJlY3RvcnkifQogICAgZmlsZXMgPSBbXQogICAgZm9yIGYgaW4g"
    "c29ydGVkKFVTRVJfRklMRVNfRElSLml0ZXJkaXIoKSk6CiAgICAgICAgaWYgZi5pc19maWxlKCkg"
    "YW5kIGYuc3VmZml4Lmxvd2VyKCkgaW4gQUxMT1dFRF9GSUxFX0VYVDoKICAgICAgICAgICAgZmls"
    "ZXMuYXBwZW5kKHsibmFtZSI6IGYubmFtZSwgInNpemUiOiBmLnN0YXQoKS5zdF9zaXplLAogICAg"
    "ICAgICAgICAgICAgICAgICAgICAgICJtb2RpZmllZCI6IGRhdGV0aW1lLmZyb210aW1lc3RhbXAo"
    "Zi5zdGF0KCkuc3RfbXRpbWUpLmlzb2Zvcm1hdCgpfSkKICAgIHJldHVybiB7ImZpbGVzIjogZmls"
    "ZXMsICJjb3VudCI6IGxlbihmaWxlcyl9CgpAYXBwLmdldCgiL2ZpbGVzL3tmaWxlbmFtZX0iKQph"
    "c3luYyBkZWYgcmVhZF9maWxlKGZpbGVuYW1lOiBzdHIsIF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tl"
    "eSkpOgogICAgdHJ5OgogICAgICAgIHBhdGggPSBfc2FmZV9wYXRoKGZpbGVuYW1lKQogICAgICAg"
    "IGlmIG5vdCBwYXRoLmV4aXN0cygpOgogICAgICAgICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKDQw"
    "NCwgZiJGaWxlIG5vdCBmb3VuZDoge2ZpbGVuYW1lfSIpCiAgICAgICAgaWYgcGF0aC5zdWZmaXgu"
    "bG93ZXIoKSBpbiAoIi5wZGYiLCAiLnhsc3giLCAiLnhscyIsICIuZG9jeCIpOgogICAgICAgICAg"
    "ICByZXR1cm4geyJuYW1lIjogZmlsZW5hbWUsICJ0eXBlIjogcGF0aC5zdWZmaXgsCiAgICAgICAg"
    "ICAgICAgICAgICAgIm1lc3NhZ2UiOiAiQmluYXJ5IGZpbGUg4oCUIHVzZSAvYnJvd3NlIHRvIGFz"
    "ayBBSSB0byBhbmFseXplIGl0In0KICAgICAgICB0ZXh0ID0gcGF0aC5yZWFkX3RleHQoInV0Zi04"
    "IiwgZXJyb3JzPSJyZXBsYWNlIilbOjUwMDAwXQogICAgICAgIHJldHVybiB7Im5hbWUiOiBmaWxl"
    "bmFtZSwgImNvbnRlbnQiOiB0ZXh0LCAic2l6ZSI6IGxlbih0ZXh0KX0KICAgIGV4Y2VwdCBWYWx1"
    "ZUVycm9yIGFzIGU6CiAgICAgICAgcmFpc2UgSFRUUEV4Y2VwdGlvbig0MDAsIHN0cihlKSkKCkBh"
    "cHAucG9zdCgiL2ZpbGVzL3tmaWxlbmFtZX0iKQpAbGltaXRlci5saW1pdCgiMTAvbWludXRlIikK"
    "YXN5bmMgZGVmIHdyaXRlX2ZpbGUocmVxdWVzdDogUmVxdWVzdCwgZmlsZW5hbWU6IHN0ciwgXz1E"
    "ZXBlbmRzKHZlcmlmeV9hcGlfa2V5KSk6CiAgICB0cnk6CiAgICAgICAgcGF0aCA9IF9zYWZlX3Bh"
    "dGgoZmlsZW5hbWUpCiAgICAgICAgYm9keSA9IGF3YWl0IHJlcXVlc3QuanNvbigpCiAgICAgICAg"
    "dGV4dCA9IHN0cihib2R5LmdldCgiY29udGVudCIsICIiKSlbOjEwMDAwMF0KICAgICAgICBVU0VS"
    "X0ZJTEVTX0RJUi5ta2RpcihwYXJlbnRzPVRydWUsIGV4aXN0X29rPVRydWUpCiAgICAgICAgcGF0"
    "aC53cml0ZV90ZXh0KHRleHQsICJ1dGYtOCIpCiAgICAgICAgYXVkaXRfbG9nZ2VyLmluZm8oZiJG"
    "SUxFX1dSSVRFfHtmaWxlbmFtZX18e2xlbih0ZXh0KX1ieXRlcyIpCiAgICAgICAgcmV0dXJuIHsi"
    "c3VjY2VzcyI6IFRydWUsICJuYW1lIjogZmlsZW5hbWUsICJzaXplIjogbGVuKHRleHQpfQogICAg"
    "ZXhjZXB0IFZhbHVlRXJyb3IgYXMgZToKICAgICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKDQwMCwg"
    "c3RyKGUpKQoKIyBbU0VDVVJJVFldIOyDge2DnCDtmZXsnbjsmqkgKOq0gOumrOyekCDsoITsmqkp"
    "CkBhcHAuZ2V0KCIvbWV0cmljcyIpCmFzeW5jIGRlZiBtZXRyaWNzKHJlcXVlc3Q6IFJlcXVlc3Qs"
    "IF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkpOgogICAgcmV0dXJuIHsKICAgICAgICAiYWN0aXZl"
    "X3Rhc2tzIjogX2FjdGl2ZV90YXNrcywKICAgICAgICAibWF4X2NvbmN1cnJlbnQiOiBNQVhfQ09O"
    "Q1VSUkVOVCwKICAgICAgICAibW9kZWwiOiBHUk9RX01PREVMLAogICAgICAgICJ0aW1lb3V0cyI6"
    "IHsKICAgICAgICAgICAgInRhc2siOiBUQVNLX1RJTUVPVVQsCiAgICAgICAgICAgICJtdWx0aSI6"
    "IE1VTFRJX1RJTUVPVVQsCiAgICAgICAgICAgICJzdGVwIjogU1RFUF9USU1FT1VUCiAgICAgICAg"
    "fQogICAgfQoKIyDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi"
    "lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi"
    "lZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDilZDi"
    "lZDilZDilZDilZDilZDilZDilZAKIyBbdjddIOqygOyDiSDsl5Trk5ztj6zsnbjtirgg4oCUIOuE"
    "pOydtOuyhCDqsoDsg4kgQVBJICsgVGF2aWx5ICjruIzrnbzsmrDsp5Ug64yA7LK0KQojIOq4sOyh"
    "tCDrs7TslYgg6rOE7Li1IOyDgeyGjTogdmVyaWZ5X2FwaV9rZXksIOqwkOyCrCDroZzqt7gsIGZp"
    "bHRlcl9yZXNwb25zZSwgcmF0ZSBsaW1pdC4KIyBBUEkg7YKk64qUIOyEnOuyhCAuZW52IOyXkOun"
    "jCDsobTsnqztlZjrqbAg7J2R64u17JeQIOuFuOy2nOuQmOyngCDslYrripTri6QuCiMg4pWQ4pWQ"
    "4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ"
    "4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ"
    "4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ"
    "4pWQCl9IQU5HVUxfUkUgPSBfcmUuY29tcGlsZShyIltcdWFjMDAtXHVkN2EzXSIpCgpkZWYgX2lz"
    "X2tvcmVhbl9xdWVyeShxKToKICAgIHJldHVybiBib29sKHEgYW5kIF9IQU5HVUxfUkUuc2VhcmNo"
    "KHEpKQoKZGVmIF9zY2FjaGVfZ2V0KG5hbWUsIHEpOgogICAgaWYgU0VBUkNIX0NBQ0hFX1RUTCA8"
    "PSAwOgogICAgICAgIHJldHVybiBOb25lCiAgICBlID0gX3NlYXJjaF9jYWNoZS5nZXQoKG5hbWUs"
    "IHEpKQogICAgaWYgZSBhbmQgKHRpbWUudGltZSgpIC0gZVsxXSkgPCBTRUFSQ0hfQ0FDSEVfVFRM"
    "OgogICAgICAgIHJldHVybiBlWzBdCiAgICByZXR1cm4gTm9uZQoKZGVmIF9zY2FjaGVfc2V0KG5h"
    "bWUsIHEsIGRhdGEpOgogICAgaWYgU0VBUkNIX0NBQ0hFX1RUTCA+IDA6CiAgICAgICAgX3NlYXJj"
    "aF9jYWNoZVsobmFtZSwgcSldID0gKGRhdGEsIHRpbWUudGltZSgpKQogICAgICAgIGlmIGxlbihf"
    "c2VhcmNoX2NhY2hlKSA+IDIwMDoKICAgICAgICAgICAgb2xkZXN0ID0gbWluKF9zZWFyY2hfY2Fj"
    "aGUsIGtleT1sYW1iZGEgazogX3NlYXJjaF9jYWNoZVtrXVsxXSkKICAgICAgICAgICAgZGVsIF9z"
    "ZWFyY2hfY2FjaGVbb2xkZXN0XQoKZGVmIF9zdHJpcF90YWdzKHMpOgogICAgcyA9IF9yZS5zdWIo"
    "ciI8W14+XSs+IiwgIiIsIHMgb3IgIiIpCiAgICByZXR1cm4gKHMucmVwbGFjZSgiJnF1b3Q7Iiwg"
    "JyInKS5yZXBsYWNlKCImYW1wOyIsICImIikKICAgICAgICAgICAgIC5yZXBsYWNlKCImbHQ7Iiwg"
    "IjwiKS5yZXBsYWNlKCImZ3Q7IiwgIj4iKS5yZXBsYWNlKCImbmJzcDsiLCAiICIpKQoKYXN5bmMg"
    "ZGVmIF9uYXZlcl9hcGlfc2VhcmNoKHF1ZXJ5LCBraW5kPSJ3ZWJrciIsIGRpc3BsYXk9NSk6CiAg"
    "ICBpZiBub3QgKE5BVkVSX0NMSUVOVF9JRCBhbmQgTkFWRVJfQ0xJRU5UX1NFQ1JFVCk6CiAgICAg"
    "ICAgcmV0dXJuIHsib2siOiBGYWxzZSwgImVycm9yIjogIk5BVkVSIGtleXMgbm90IGNvbmZpZ3Vy"
    "ZWQiLCAiaXRlbXMiOiBbXX0KICAgIGNhY2hlZCA9IF9zY2FjaGVfZ2V0KCJuYXZlcjoiICsga2lu"
    "ZCwgcXVlcnkpCiAgICBpZiBjYWNoZWQgaXMgbm90IE5vbmU6CiAgICAgICAgcmV0dXJuIGNhY2hl"
    "ZAogICAgaW1wb3J0IGh0dHB4CiAgICBlbmRwb2ludCA9IHsKICAgICAgICAid2Via3IiOiAiaHR0"
    "cHM6Ly9vcGVuYXBpLm5hdmVyLmNvbS92MS9zZWFyY2gvd2Via3IuanNvbiIsCiAgICAgICAgIm5l"
    "d3MiOiAgImh0dHBzOi8vb3BlbmFwaS5uYXZlci5jb20vdjEvc2VhcmNoL25ld3MuanNvbiIsCiAg"
    "ICAgICAgImJsb2ciOiAgImh0dHBzOi8vb3BlbmFwaS5uYXZlci5jb20vdjEvc2VhcmNoL2Jsb2cu"
    "anNvbiIsCiAgICAgICAgImVuY3ljIjogImh0dHBzOi8vb3BlbmFwaS5uYXZlci5jb20vdjEvc2Vh"
    "cmNoL2VuY3ljLmpzb24iLAogICAgICAgICJsb2NhbCI6ICJodHRwczovL29wZW5hcGkubmF2ZXIu"
    "Y29tL3YxL3NlYXJjaC9sb2NhbC5qc29uIiwKICAgIH0uZ2V0KGtpbmQsICJodHRwczovL29wZW5h"
    "cGkubmF2ZXIuY29tL3YxL3NlYXJjaC93ZWJrci5qc29uIikKICAgIGhlYWRlcnMgPSB7IlgtTmF2"
    "ZXItQ2xpZW50LUlkIjogTkFWRVJfQ0xJRU5UX0lELAogICAgICAgICAgICAgICAiWC1OYXZlci1D"
    "bGllbnQtU2VjcmV0IjogTkFWRVJfQ0xJRU5UX1NFQ1JFVH0KICAgIHBhcmFtcyA9IHsicXVlcnki"
    "OiBxdWVyeSwgImRpc3BsYXkiOiBtYXgoMSwgbWluKGRpc3BsYXksIDEwKSl9CiAgICB0cnk6CiAg"
    "ICAgICAgYXN5bmMgd2l0aCBodHRweC5Bc3luY0NsaWVudCh0aW1lb3V0PVNFQVJDSF9USU1FT1VU"
    "KSBhcyBjOgogICAgICAgICAgICByID0gYXdhaXQgYy5nZXQoZW5kcG9pbnQsIGhlYWRlcnM9aGVh"
    "ZGVycywgcGFyYW1zPXBhcmFtcykKICAgICAgICBpZiByLnN0YXR1c19jb2RlICE9IDIwMDoKICAg"
    "ICAgICAgICAgcmV0dXJuIHsib2siOiBGYWxzZSwgImVycm9yIjogIm5hdmVyIGh0dHAgJXMiICUg"
    "ci5zdGF0dXNfY29kZSwgIml0ZW1zIjogW119CiAgICAgICAgZGF0YSA9IHIuanNvbigpCiAgICAg"
    "ICAgaXRlbXMgPSBbeyJ0aXRsZSI6IF9zdHJpcF90YWdzKGl0LmdldCgidGl0bGUiLCAiIikpLAog"
    "ICAgICAgICAgICAgICAgICAic25pcHBldCI6IF9zdHJpcF90YWdzKGl0LmdldCgiZGVzY3JpcHRp"
    "b24iLCAiIikpLAogICAgICAgICAgICAgICAgICAidXJsIjogaXQuZ2V0KCJsaW5rIiwgIiIpfSBm"
    "b3IgaXQgaW4gZGF0YS5nZXQoIml0ZW1zIiwgW10pXQogICAgICAgIG91dCA9IHsib2siOiBUcnVl"
    "LCAic291cmNlIjogIm5hdmVyOiIgKyBraW5kLCAiaXRlbXMiOiBpdGVtc30KICAgICAgICBfc2Nh"
    "Y2hlX3NldCgibmF2ZXI6IiArIGtpbmQsIHF1ZXJ5LCBvdXQpCiAgICAgICAgcmV0dXJuIG91dAog"
    "ICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgIHJldHVybiB7Im9rIjogRmFsc2UsICJl"
    "cnJvciI6ICJuYXZlcjogJXMiICUgZSwgIml0ZW1zIjogW119Cgphc3luYyBkZWYgX3RhdmlseV9z"
    "ZWFyY2gocXVlcnksIG1heF9yZXN1bHRzPTUpOgogICAgaWYgbm90IFRBVklMWV9BUElfS0VZOgog"
    "ICAgICAgIHJldHVybiB7Im9rIjogRmFsc2UsICJlcnJvciI6ICJUQVZJTFkga2V5IG5vdCBjb25m"
    "aWd1cmVkIiwgIml0ZW1zIjogW10sICJhbnN3ZXIiOiAiIn0KICAgIGNhY2hlZCA9IF9zY2FjaGVf"
    "Z2V0KCJ0YXZpbHkiLCBxdWVyeSkKICAgIGlmIGNhY2hlZCBpcyBub3QgTm9uZToKICAgICAgICBy"
    "ZXR1cm4gY2FjaGVkCiAgICBpbXBvcnQgaHR0cHgKICAgIHRyeToKICAgICAgICBhc3luYyB3aXRo"
    "IGh0dHB4LkFzeW5jQ2xpZW50KHRpbWVvdXQ9U0VBUkNIX1RJTUVPVVQpIGFzIGM6CiAgICAgICAg"
    "ICAgIHIgPSBhd2FpdCBjLnBvc3QoImh0dHBzOi8vYXBpLnRhdmlseS5jb20vc2VhcmNoIiwganNv"
    "bj17CiAgICAgICAgICAgICAgICAiYXBpX2tleSI6IFRBVklMWV9BUElfS0VZLCAicXVlcnkiOiBx"
    "dWVyeSwKICAgICAgICAgICAgICAgICJtYXhfcmVzdWx0cyI6IG1heCgxLCBtaW4obWF4X3Jlc3Vs"
    "dHMsIDEwKSksCiAgICAgICAgICAgICAgICAiaW5jbHVkZV9hbnN3ZXIiOiBUcnVlLCAic2VhcmNo"
    "X2RlcHRoIjogImJhc2ljIn0pCiAgICAgICAgaWYgci5zdGF0dXNfY29kZSAhPSAyMDA6CiAgICAg"
    "ICAgICAgIHJldHVybiB7Im9rIjogRmFsc2UsICJlcnJvciI6ICJ0YXZpbHkgaHR0cCAlcyIgJSBy"
    "LnN0YXR1c19jb2RlLCAiaXRlbXMiOiBbXSwgImFuc3dlciI6ICIifQogICAgICAgIGRhdGEgPSBy"
    "Lmpzb24oKQogICAgICAgIGl0ZW1zID0gW3sidGl0bGUiOiBpdC5nZXQoInRpdGxlIiwgIiIpLCAi"
    "c25pcHBldCI6IGl0LmdldCgiY29udGVudCIsICIiKSwKICAgICAgICAgICAgICAgICAgInVybCI6"
    "IGl0LmdldCgidXJsIiwgIiIpfSBmb3IgaXQgaW4gZGF0YS5nZXQoInJlc3VsdHMiLCBbXSldCiAg"
    "ICAgICAgb3V0ID0geyJvayI6IFRydWUsICJzb3VyY2UiOiAidGF2aWx5IiwgImFuc3dlciI6IGRh"
    "dGEuZ2V0KCJhbnN3ZXIiLCAiIiksICJpdGVtcyI6IGl0ZW1zfQogICAgICAgIF9zY2FjaGVfc2V0"
    "KCJ0YXZpbHkiLCBxdWVyeSwgb3V0KQogICAgICAgIHJldHVybiBvdXQKICAgIGV4Y2VwdCBFeGNl"
    "cHRpb24gYXMgZToKICAgICAgICByZXR1cm4geyJvayI6IEZhbHNlLCAiZXJyb3IiOiAidGF2aWx5"
    "OiAlcyIgJSBlLCAiaXRlbXMiOiBbXSwgImFuc3dlciI6ICIifQoKZGVmIF9mb3JtYXRfc2VhcmNo"
    "X3Jlc3VsdHMocmVzKToKICAgIGlmIG5vdCByZXMuZ2V0KCJvayIpOgogICAgICAgIHJldHVybiAi"
    "6rKA7IOJIOyLpO2MqDogJXMiICUgcmVzLmdldCgiZXJyb3IiLCAi7JWMIOyImCDsl4bripQg7Jik"
    "66WYIikKICAgIGxpbmVzID0gW10KICAgIGlmIHJlcy5nZXQoImFuc3dlciIpOgogICAgICAgIGxp"
    "bmVzLmFwcGVuZCgi7JqU7JW9OiAiICsgcmVzWyJhbnN3ZXIiXSk7IGxpbmVzLmFwcGVuZCgiIikK"
    "ICAgIGZvciBpLCBpdCBpbiBlbnVtZXJhdGUocmVzLmdldCgiaXRlbXMiLCBbXSksIDEpOgogICAg"
    "ICAgIHQgPSAoaXQuZ2V0KCJ0aXRsZSIpIG9yICIiKS5zdHJpcCgpCiAgICAgICAgc24gPSAoaXQu"
    "Z2V0KCJzbmlwcGV0Iikgb3IgIiIpLnN0cmlwKCkKICAgICAgICB1ID0gKGl0LmdldCgidXJsIikg"
    "b3IgIiIpLnN0cmlwKCkKICAgICAgICBibG9jayA9ICgiJWQuICVzIiAlIChpLCB0KSkgaWYgdCBl"
    "bHNlICgiJWQuIiAlIGkpCiAgICAgICAgaWYgc246CiAgICAgICAgICAgIGJsb2NrICs9ICJcbiAg"
    "ICIgKyBzbgogICAgICAgIGlmIHU6CiAgICAgICAgICAgIGJsb2NrICs9ICJcbiAgICIgKyB1CiAg"
    "ICAgICAgbGluZXMuYXBwZW5kKGJsb2NrKQogICAgcmV0dXJuICJcbiIuam9pbihsaW5lcykgaWYg"
    "bGluZXMgZWxzZSAi6rKA7IOJIOqysOqzvOqwgCDsl4bsirXri4jri6QuIgoKY2xhc3MgU2VhcmNo"
    "UmVxdWVzdChCYXNlTW9kZWwpOgogICAgcXVlcnk6IHN0ciA9IEZpZWxkKC4uLiwgbWluX2xlbmd0"
    "aD0xLCBtYXhfbGVuZ3RoPTUwMCkKICAgIGtpbmQ6IHN0ciA9IEZpZWxkKGRlZmF1bHQ9ImF1dG8i"
    "LCBtYXhfbGVuZ3RoPTIwKQogICAgZGlzcGxheTogaW50ID0gRmllbGQoZGVmYXVsdD01LCBnZT0x"
    "LCBsZT0xMCkKCkBhcHAucG9zdCgiL3NlYXJjaCIpCkBsaW1pdGVyLmxpbWl0KCIyMC9taW51dGUi"
    "KQphc3luYyBkZWYgc2VhcmNoKHJlcXVlc3Q6IFJlcXVlc3QsIGJvZHk6IFNlYXJjaFJlcXVlc3Qs"
    "IF89RGVwZW5kcyh2ZXJpZnlfYXBpX2tleSkpOgogICAgIiIi64Sk7J2067KEIOqygOyDiSBBUEkg"
    "KyBUYXZpbHkg7ZWY7J2067iM66as65OcLiDtlZzqta3slrTihpLrhKTsnbTrsoQsIOq3uCDsmbji"
    "hpJUYXZpbHkuIiIiCiAgICBxID0gYm9keS5xdWVyeS5zdHJpcCgpCiAgICBpZiBub3QgcToKICAg"
    "ICAgICByYWlzZSBIVFRQRXhjZXB0aW9uKDQwMCwgImVtcHR5IHF1ZXJ5IikKICAgIGNpcCA9IHJl"
    "cXVlc3QuY2xpZW50Lmhvc3QgaWYgcmVxdWVzdC5jbGllbnQgZWxzZSAiPyIKICAgIGF1ZGl0X2xv"
    "Z2dlci5pbmZvKCJTRUFSQ0h8JXN8a2luZD0lc3wlcyIgJSAoY2lwLCBib2R5LmtpbmQsIHFbOjgw"
    "XSkpCiAgICBraW5kID0gYm9keS5raW5kLmxvd2VyKCkKICAgIGlmIGtpbmQgaW4gKCJ3ZWJrciIs"
    "ICJuZXdzIiwgImJsb2ciLCAiZW5jeWMiLCAibG9jYWwiKToKICAgICAgICByZXMgPSBhd2FpdCBf"
    "bmF2ZXJfYXBpX3NlYXJjaChxLCBraW5kLCBib2R5LmRpc3BsYXkpOyByb3V0ZWQgPSAibmF2ZXI6"
    "IiArIGtpbmQKICAgIGVsaWYga2luZCA9PSAid2ViIjoKICAgICAgICByZXMgPSBhd2FpdCBfdGF2"
    "aWx5X3NlYXJjaChxLCBib2R5LmRpc3BsYXkpOyByb3V0ZWQgPSAidGF2aWx5IgogICAgZWxzZToK"
    "ICAgICAgICBpZiBfaXNfa29yZWFuX3F1ZXJ5KHEpOgogICAgICAgICAgICByZXMgPSBhd2FpdCBf"
    "bmF2ZXJfYXBpX3NlYXJjaChxLCAid2Via3IiLCBib2R5LmRpc3BsYXkpOyByb3V0ZWQgPSAibmF2"
    "ZXI6d2Via3IiCiAgICAgICAgICAgIGlmIG5vdCByZXMuZ2V0KCJvayIpIG9yIG5vdCByZXMuZ2V0"
    "KCJpdGVtcyIpOgogICAgICAgICAgICAgICAgdHYgPSBhd2FpdCBfdGF2aWx5X3NlYXJjaChxLCBi"
    "b2R5LmRpc3BsYXkpCiAgICAgICAgICAgICAgICBpZiB0di5nZXQoIm9rIikgYW5kIHR2LmdldCgi"
    "aXRlbXMiKToKICAgICAgICAgICAgICAgICAgICByZXMsIHJvdXRlZCA9IHR2LCAidGF2aWx5KGZh"
    "bGxiYWNrKSIKICAgICAgICBlbHNlOgogICAgICAgICAgICByZXMgPSBhd2FpdCBfdGF2aWx5X3Nl"
    "YXJjaChxLCBib2R5LmRpc3BsYXkpOyByb3V0ZWQgPSAidGF2aWx5IgogICAgICAgICAgICBpZiBu"
    "b3QgcmVzLmdldCgib2siKSBvciBub3QgcmVzLmdldCgiaXRlbXMiKToKICAgICAgICAgICAgICAg"
    "IG52ID0gYXdhaXQgX25hdmVyX2FwaV9zZWFyY2gocSwgIndlYmtyIiwgYm9keS5kaXNwbGF5KQog"
    "ICAgICAgICAgICAgICAgaWYgbnYuZ2V0KCJvayIpIGFuZCBudi5nZXQoIml0ZW1zIik6CiAgICAg"
    "ICAgICAgICAgICAgICAgcmVzLCByb3V0ZWQgPSBudiwgIm5hdmVyOndlYmtyKGZhbGxiYWNrKSIK"
    "ICAgIHRleHQgPSBfZm9ybWF0X3NlYXJjaF9yZXN1bHRzKHJlcykKICAgIHRyeToKICAgICAgICB0"
    "ZXh0ID0gZmlsdGVyX3Jlc3BvbnNlKHRleHQpCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAg"
    "IHBhc3MKICAgIG9rID0gYm9vbChyZXMuZ2V0KCJvayIpIGFuZCByZXMuZ2V0KCJpdGVtcyIpKQog"
    "ICAgYXVkaXRfbG9nZ2VyLmluZm8oIlNFQVJDSF8lc3xyb3V0ZWQ9JXN8aXRlbXM9JWQiICUKICAg"
    "ICAgICAgICAgICAgICAgICAgICgiT0siIGlmIG9rIGVsc2UgIkVNUFRZIiwgcm91dGVkLCBsZW4o"
    "cmVzLmdldCgiaXRlbXMiLCBbXSkpKSkKICAgIHJldHVybiB7InN1Y2Nlc3MiOiBvaywgInJvdXRl"
    "ZCI6IHJvdXRlZCwgInF1ZXJ5IjogcSwKICAgICAgICAgICAgImFuc3dlciI6IHJlcy5nZXQoImFu"
    "c3dlciIsICIiKSwgInJlc3VsdHMiOiByZXMuZ2V0KCJpdGVtcyIsIFtdKSwKICAgICAgICAgICAg"
    "InN1bW1hcnlfcGxhaW4iOiB0ZXh0LCAic3VtbWFyeSI6IHRleHQsCiAgICAgICAgICAgICJ0aW1l"
    "c3RhbXAiOiBkYXRldGltZS5ub3coKS5pc29mb3JtYXQoKX0KCgppZiBfX25hbWVfXyA9PSAiX19t"
    "YWluX18iOgogICAgaW1wb3J0IHV2aWNvcm4KICAgIHV2aWNvcm4ucnVuKGFwcCwgaG9zdD0iMC4w"
    "LjAuMCIsIHBvcnQ9ODAwMSwKICAgICAgICAgICAgICAgIHNlcnZlcl9oZWFkZXI9RmFsc2UsICAj"
    "IFtTRUNVUklUWV0g7ISc67KEIO2XpOuNlCDsiKjquYAKICAgICAgICAgICAgICAgIGFjY2Vzc19s"
    "b2c9VHJ1ZSkK"
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
    "lOuTnO2PrOyduO2KuCDtmLjstpwgKOuEpOydtOuyhCBBUEkgKyBUYXZpbHkpLgogICAgICAgIOu4"
    "jOudvOyasOyggCDquIHquLAg64yA7IugIOqzteyLnSDqsoDsg4kgQVBJIOulvCDsgqzsmqntlZzr"
    "i6QuIiIiCiAgICAgICAgY2FjaGVkID0gc2VsZi5fZ2V0X2NhY2hlKCJzZWFyY2g6JXM6JXMiICUg"
    "KGtpbmQsIHF1ZXJ5KSkKICAgICAgICBpZiBjYWNoZWQ6IHJldHVybiBjYWNoZWQKICAgICAgICBh"
    "c3luYyBkZWYgZW1pdChtc2csIGRvbmU9RmFsc2UpOgogICAgICAgICAgICBpZiBfX2V2ZW50X2Vt"
    "aXR0ZXJfXzogYXdhaXQgX19ldmVudF9lbWl0dGVyX18oeyJ0eXBlIjoic3RhdHVzIiwiZGF0YSI6"
    "eyJkZXNjcmlwdGlvbiI6bXNnLCJkb25lIjpkb25lfX0pCiAgICAgICAgYXdhaXQgZW1pdCgi6rKA"
    "7IOJIOykkS4uLiIpCiAgICAgICAgdHJ5OgogICAgICAgICAgICByZXN1bHQgPSBhd2FpdCBzZWxm"
    "Ll9wb3N0KCIvc2VhcmNoIiwgeyJxdWVyeSI6IHF1ZXJ5LCAia2luZCI6IGtpbmQsICJkaXNwbGF5"
    "IjogZGlzcGxheX0pCiAgICAgICAgICAgIHRleHQgPSByZXN1bHQuZ2V0KCJzdW1tYXJ5X3BsYWlu"
    "Iikgb3IgcmVzdWx0LmdldCgic3VtbWFyeSIsICIiKQogICAgICAgICAgICBhd2FpdCBlbWl0KCLs"
    "mYTro4whIiwgZG9uZT1UcnVlKQogICAgICAgICAgICBpZiB0ZXh0OiBzZWxmLl9zZXRfY2FjaGUo"
    "InNlYXJjaDolczolcyIgJSAoa2luZCwgcXVlcnkpLCB0ZXh0KQogICAgICAgICAgICByZXR1cm4g"
    "dGV4dCBvciAi6rKA7IOJIOqysOqzvOqwgCDsl4bsirXri4jri6QuIgogICAgICAgIGV4Y2VwdCBF"
    "eGNlcHRpb24gYXMgZToKICAgICAgICAgICAgYXdhaXQgZW1pdCgi7Jik66WYIiwgZG9uZT1UcnVl"
    "KQogICAgICAgICAgICByZXR1cm4gIuqygOyDiSDsmKTrpZg6ICVzIiAlIGUKCiAgICBhc3luYyBk"
    "ZWYgX25hdmVyX3NlYXJjaChzZWxmLCBxdWVyeV9rciwgaW5zdHJ1Y3Rpb24sIF9fZXZlbnRfZW1p"
    "dHRlcl9fPU5vbmUpOgogICAgICAgICMgW3Y3XSDruIzrnbzsmrDsoIAg6riB6riwIOKGkiAvc2Vh"
    "cmNoIOyXlOuTnO2PrOyduO2KuCjrhKTsnbTrsoQgQVBJKS4gaW5zdHJ1Y3Rpb24g7J2ACiAgICAg"
    "ICAgIyBBUEkg6rKA7IOJ7JeQ7ISc64qUIOu2iO2VhOyalO2VmOuvgOuhnCDrrLTsi5ztlZjqs6Ag"
    "cXVlcnkg66eMIOyCrOyaqe2VnOuLpC4KICAgICAgICByZXR1cm4gYXdhaXQgc2VsZi5fYXBpX3Nl"
    "YXJjaChxdWVyeV9rciwga2luZD0iYXV0byIsIF9fZXZlbnRfZW1pdHRlcl9fPV9fZXZlbnRfZW1p"
    "dHRlcl9fKQoKICAgIGRlZiBfdHJhbnNsYXRlX2tleXdvcmQoc2VsZiwga2V5d29yZDogc3RyLCBr"
    "ZXl3b3JkX21hcDogZGljdCkgLT4gc3RyOgogICAgICAgICMg7JiB7Ja0IO2CpOybjOuTnOulvCDt"
    "lZzqta3slrTroZwg7LmY7ZmY7ZWc64ukLgogICAgICAgICMgLSDsoITssrTqsIAg7KCV7ZmV7Z6I"
    "IOydvOy5mO2VmOuptCDrsJTroZwg66ek7ZWR6rCSIOuwmO2ZmAogICAgICAgICMgLSDrtoDrtoQg"
    "7LmY7ZmY7J2AICfri6jslrQg6rK96rOEJ+yXkOyEnOunjCDsiJjtlokgKG5ld3NsZXR0ZXIg7JWI"
    "7J2YIG5ld3Mg7Jik66ek7LmtIOuwqeyngCkKICAgICAgICAjIC0g66ek7Lmt65CY7KeAIOyViuyd"
    "gCDrtoDrtoTsnYAg7JuQ66y4IOuMgOyGjOusuOyekOulvCDqt7jrjIDroZwg67O07KG0CiAgICAg"
    "ICAgaW1wb3J0IHJlIGFzIF9yZQogICAgICAgIGt3ID0ga2V5d29yZC5zdHJpcCgpCiAgICAgICAg"
    "aWYga3cubG93ZXIoKSBpbiBrZXl3b3JkX21hcDoKICAgICAgICAgICAgcmV0dXJuIGtleXdvcmRf"
    "bWFwW2t3Lmxvd2VyKCldCiAgICAgICAgZm9yIGVuZywga29yIGluIHNvcnRlZChrZXl3b3JkX21h"
    "cC5pdGVtcygpLCBrZXk9bGFtYmRhIHg6IC1sZW4oeFswXSkpOgogICAgICAgICAgICBwYXR0ZXJu"
    "ID0gcicoPzwhW0EtWmEtejAtOV0pJyArIF9yZS5lc2NhcGUoZW5nKSArIHInKD8hW0EtWmEtejAt"
    "OV0pJwogICAgICAgICAgICBpZiBfcmUuc2VhcmNoKHBhdHRlcm4sIGt3LCBmbGFncz1fcmUuSUdO"
    "T1JFQ0FTRSk6CiAgICAgICAgICAgICAgICByZXR1cm4gX3JlLnN1YihwYXR0ZXJuLCBrb3IsIGt3"
    "LCBmbGFncz1fcmUuSUdOT1JFQ0FTRSkKICAgICAgICByZXR1cm4ga2V5d29yZAoKICAgIGFzeW5j"
    "IGRlZiBzZWFyY2hfbmF2ZXIoc2VsZiwga2V5d29yZDogc3RyLCBfX2V2ZW50X2VtaXR0ZXJfXz1O"
    "b25lKToKICAgICAgICAiIiJTZWFyY2ggTmF2ZXIgZm9yIHJlYWwtdGltZSBpbmZvcm1hdGlvbi4K"
    "ICAgICAgICA6cGFyYW0ga2V5d29yZDogU2VhcmNoIGtleXdvcmQKICAgICAgICAiIiIKICAgICAg"
    "ICBpZiBub3Qga2V5d29yZC5zdHJpcCgpOiByZXR1cm4gIuqygOyDieyWtOulvCDsnoXroKXtlZjs"
    "hLjsmpQuIgogICAgICAgIGttID0geyJ3ZWF0aGVyIjoi64Kg7JSoIiwibmV3cyI6IuuJtOyKpCIs"
    "InN0b2NrIjoi7KO86rCAIiwiZXhjaGFuZ2UgcmF0ZSI6Iu2ZmOycqCIsInByaWNlIjoi6rCA6rKp"
    "IiwKICAgICAgICAgICAgICAiYml0Y29pbiI6Iuu5hO2KuOy9lOyduCIsInNvY2NlciI6Iuy2leq1"
    "rCIsImJhc2ViYWxsIjoi7JW86rWsIiwibW92aWUiOiLsmIHtmZQiLCJ0cmF2ZWwiOiLsl6ztloki"
    "fQogICAgICAgIHJldHVybiBhd2FpdCBzZWxmLl9uYXZlcl9zZWFyY2goc2VsZi5fdHJhbnNsYXRl"
    "X2tleXdvcmQoa2V5d29yZCwga20pLAogICAgICAgICAgICAicmVhZCB0aGUga2V5IGluZm9ybWF0"
    "aW9uIGZyb20gc2VhcmNoIHJlc3VsdHMgaW4gS29yZWFuIiwgX19ldmVudF9lbWl0dGVyX18pCgog"
    "ICAgYXN5bmMgZGVmIHRyYW5zbGF0ZShzZWxmLCB0ZXh0OiBzdHIsIHRhcmdldF9sYW5nOiBzdHIg"
    "PSAi7ZWc6rWt7Ja0IiwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiVHJhbnNs"
    "YXRlIHRleHQgYmV0d2VlbiBsYW5ndWFnZXMgKEtvcmVhbiwgRW5nbGlzaCwgSmFwYW5lc2UsIENo"
    "aW5lc2UsIGV0YykuCiAgICAgICAgOnBhcmFtIHRleHQ6IOuyiOyXre2VoCDsm5DrrLgKICAgICAg"
    "ICA6cGFyYW0gdGFyZ2V0X2xhbmc6IOuqqe2RnCDslrjslrQgKOyYiDog7ZWc6rWt7Ja0LCDsmIHs"
    "lrQsIOydvOuzuOyWtCwg7KSR6rWt7Ja0KS4g6riw67O4IO2VnOq1reyWtC4KICAgICAgICAiIiIK"
    "ICAgICAgICBzcmMgPSAodGV4dCBvciAiIikuc3RyaXAoKQogICAgICAgIGlmIG5vdCBzcmM6IHJl"
    "dHVybiAi67KI7Jet7ZWgIOuCtOyaqeydhCDsnoXroKXtlZjshLjsmpQuIgogICAgICAgIHRndCA9"
    "ICh0YXJnZXRfbGFuZyBvciAiIikuc3RyaXAoKSBvciAi7ZWc6rWt7Ja0IgogICAgICAgIGlmIGxl"
    "bihzcmMpID4gMzAwMDogc3JjID0gc3JjWzozMDAwXQogICAgICAgIGNhY2hlX2tleSA9ICJ0cjoi"
    "ICsgdGd0ICsgIjoiICsgc3JjWzo4MF0KICAgICAgICBjYWNoZWQgPSBzZWxmLl9nZXRfY2FjaGUo"
    "Y2FjaGVfa2V5KQogICAgICAgIGlmIGNhY2hlZDogcmV0dXJuIGNhY2hlZAogICAgICAgIGFzeW5j"
    "IGRlZiBlbWl0KG1zZywgZG9uZT1GYWxzZSk6CiAgICAgICAgICAgIGlmIF9fZXZlbnRfZW1pdHRl"
    "cl9fOiBhd2FpdCBfX2V2ZW50X2VtaXR0ZXJfXyh7InR5cGUiOiJzdGF0dXMiLCJkYXRhIjp7ImRl"
    "c2NyaXB0aW9uIjptc2csImRvbmUiOmRvbmV9fSkKICAgICAgICBhd2FpdCBlbWl0KHRndCArICIo"
    "7Jy8KeuhnCDrsojsl60g7KSRLi4uIikKICAgICAgICB0cnk6CiAgICAgICAgICAgIHRhc2sgPSAo"
    "IuuLpOydjCDthY3siqTtirjrpbwgIiArIHRndCArICLroZwg67KI7Jet7ZWY7IS47JqULiDrsojs"
    "l60g6rKw6rO866eMIOy2nOugpe2VmOqzoCDshKTrqoXsnYAg67aZ7J207KeAIOuniOyEuOyalC5c"
    "blxuIiArIHNyYykKICAgICAgICAgICAgcmVzdWx0ID0gYXdhaXQgc2VsZi5fcG9zdCgiL2Jyb3dz"
    "ZSIsIHsidGFzayI6IHRhc2ssICJtYXhfc3RlcHMiOiAxfSkKICAgICAgICAgICAgb3V0ID0gcmVz"
    "dWx0LmdldCgic3VtbWFyeV9wbGFpbiIpIG9yIHJlc3VsdC5nZXQoInN1bW1hcnkiLCAiIikKICAg"
    "ICAgICAgICAgYXdhaXQgZW1pdCgi7JmE66OMISIsIGRvbmU9VHJ1ZSkKICAgICAgICAgICAgaWYg"
    "b3V0OiBzZWxmLl9zZXRfY2FjaGUoY2FjaGVfa2V5LCBvdXQpCiAgICAgICAgICAgIHJldHVybiBv"
    "dXQgb3IgIuuyiOyXrSDqsrDqs7zrpbwg6rCA7KC47Jik7KeAIOuqu+2WiOyKteuLiOuLpC4iCiAg"
    "ICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgICAgICBhd2FpdCBlbWl0KCLsmKTr"
    "pZgiLCBkb25lPVRydWUpCiAgICAgICAgICAgIHJldHVybiAi67KI7JetIOyYpOulmDogIiArIHN0"
    "cihlKQoKICAgIGFzeW5jIGRlZiBjaGVja193ZWF0aGVyKHNlbGYsIGxvY2F0aW9uOiBzdHIgPSAi"
    "7ISc7Jq4Iiwgd2hlbjogc3RyID0gIuyYpOuKmCIsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgog"
    "ICAgICAgICIiIkNoZWNrIHdlYXRoZXIgZnJvbSBOYXZlci4gVXNlIGZvciB3ZWF0aGVyLCB0ZW1w"
    "ZXJhdHVyZSwgcmFpbiwgdW1icmVsbGEsIGZpbmUgZHVzdCBxdWVzdGlvbnMuCiAgICAgICAgOnBh"
    "cmFtIGxvY2F0aW9uOiDsp4Dsl63rqoUgKOyYiDog7ISc7Jq4LCDrtoDsgrAsIOygnOyjvCkuIOyC"
    "rOyaqeyekOqwgCDsp4Dsl63snYQg66eQ7ZWY7KeAIOyViuycvOuptCDshJzsmrguCiAgICAgICAg"
    "OnBhcmFtIHdoZW46IOyLnOygkCAo7Jik64qYLCDrgrTsnbwsIOuqqOugiCwg7KO866eQLCDsnbTr"
    "sojso7wpLiDsi5zsoJDsnYQg66eQ7ZWY7KeAIOyViuycvOuptCDsmKTripguCiAgICAgICAgIiIi"
    "CiAgICAgICAgbG9jID0gKGxvY2F0aW9uIG9yICIiKS5zdHJpcCgpIG9yICLshJzsmrgiCiAgICAg"
    "ICAgd2ggPSAod2hlbiBvciAiIikuc3RyaXAoKSBvciAi7Jik64qYIgogICAgICAgIGNhY2hlX2tl"
    "eSA9ICJ3ZWF0aGVyOiIgKyBsb2MgKyAiOiIgKyB3aAogICAgICAgIGNhY2hlZCA9IHNlbGYuX2dl"
    "dF9jYWNoZShjYWNoZV9rZXkpCiAgICAgICAgaWYgY2FjaGVkOiByZXR1cm4gY2FjaGVkCiAgICAg"
    "ICAgYXN5bmMgZGVmIGVtaXQobXNnLCBkb25lPUZhbHNlKToKICAgICAgICAgICAgaWYgX19ldmVu"
    "dF9lbWl0dGVyX186IGF3YWl0IF9fZXZlbnRfZW1pdHRlcl9fKHsidHlwZSI6InN0YXR1cyIsImRh"
    "dGEiOnsiZGVzY3JpcHRpb24iOm1zZywiZG9uZSI6ZG9uZX19KQogICAgICAgIGF3YWl0IGVtaXQo"
    "bG9jICsgIiAiICsgd2ggKyAiIOuCoOyUqCDtmZXsnbgg7KSRLi4uIikKICAgICAgICB0cnk6CiAg"
    "ICAgICAgICAgIHdlYXRoZXIgPSBhd2FpdCBzZWxmLl9hcGlfc2VhcmNoKGxvYyArICIgIiArIHdo"
    "ICsgIiDrgqDslKgg6riw7JioIOuvuOyEuOuovOyngCIsIGtpbmQ9ImF1dG8iLCBfX2V2ZW50X2Vt"
    "aXR0ZXJfXz1fX2V2ZW50X2VtaXR0ZXJfXykKICAgICAgICAgICAgYXdhaXQgZW1pdCgi7JmE66OM"
    "ISIsIGRvbmU9VHJ1ZSkKICAgICAgICAgICAgaWYgd2VhdGhlciBhbmQgIuqygOyDiSDqsrDqs7wi"
    "IG5vdCBpbiB3ZWF0aGVyWzo4XSBhbmQgIuyYpOulmCIgbm90IGluIHdlYXRoZXJbOjZdOgogICAg"
    "ICAgICAgICAgICAgc2VsZi5fc2V0X2NhY2hlKGNhY2hlX2tleSwgd2VhdGhlcikKICAgICAgICAg"
    "ICAgcmV0dXJuIHdlYXRoZXIgb3IgKGxvYyArICIgIiArIHdoICsgIiDrgqDslKgg7KCV67O066W8"
    "IOqwgOyguOyYpOyngCDrqrvtlojsirXri4jri6QuIikKICAgICAgICBleGNlcHQgRXhjZXB0aW9u"
    "IGFzIGU6CiAgICAgICAgICAgIGF3YWl0IGVtaXQoIuyYpOulmCIsIGRvbmU9VHJ1ZSkKICAgICAg"
    "ICAgICAgcmV0dXJuICLrgqDslKgg7ZmV7J24IOyYpOulmDogIiArIHN0cihlKQoKICAgIGFzeW5j"
    "IGRlZiBjaGVja19wcmljZShzZWxmLCBwcm9kdWN0OiBzdHIsIF9fZXZlbnRfZW1pdHRlcl9fPU5v"
    "bmUpOgogICAgICAgICIiIlNlYXJjaCBwcm9kdWN0IHByaWNlcyBvbiBOYXZlciBTaG9wcGluZy4K"
    "ICAgICAgICA6cGFyYW0gcHJvZHVjdDogUHJvZHVjdCBuYW1lCiAgICAgICAgIiIiCiAgICAgICAg"
    "aWYgbm90IHByb2R1Y3Quc3RyaXAoKTogcmV0dXJuICLsg4HtkojrqoXsnYQg7J6F66Cl7ZWY7IS4"
    "7JqULiIKICAgICAgICBwbSA9IHsiYWlycG9kcyI6IuyXkOyWtO2MnyIsImFpcnBvZHMgcHJvIjoi"
    "7JeQ7Ja07YyfIO2UhOuhnCIsImlwaG9uZSI6IuyVhOydtO2PsCIsImdhbGF4eSI6IuqwpOufreyL"
    "nCIsCiAgICAgICAgICAgICAgIm1hY2Jvb2siOiLrp6XrtoEiLCJpcGFkIjoi7JWE7J207Yyo65Oc"
    "IiwibmludGVuZG8gc3dpdGNoIjoi64uM7YWQ64+EIOyKpOychOy5mCIsInBzNSI6Iu2UjOugiOyd"
    "tOyKpO2FjOydtOyFmDUifQogICAgICAgIHJldHVybiBhd2FpdCBzZWxmLl9uYXZlcl9zZWFyY2go"
    "c2VsZi5fdHJhbnNsYXRlX2tleXdvcmQocHJvZHVjdCwgcG0pICsgIiDqsIDqsqkiLAogICAgICAg"
    "ICAgICAiZmluZCBsb3dlc3QgcHJpY2UsIHN0b3JlIG5hbWUsIGRlbGl2ZXJ5IGluZm8uIFJlc3Bv"
    "bmQgaW4gS29yZWFuLiIsIF9fZXZlbnRfZW1pdHRlcl9fKQoKICAgIGFzeW5jIGRlZiBjaGVja19z"
    "dG9jayhzZWxmLCBjb21wYW55OiBzdHIsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAg"
    "ICIiIkNoZWNrIHN0b2NrIHByaWNlIGFuZCBtYXJrZXQgZGF0YS4KICAgICAgICA6cGFyYW0gY29t"
    "cGFueTogQ29tcGFueSBuYW1lCiAgICAgICAgIiIiCiAgICAgICAgaWYgbm90IGNvbXBhbnkuc3Ry"
    "aXAoKTogcmV0dXJuICLtmozsgqzrqoXsnYQg7J6F66Cl7ZWY7IS47JqULiIKICAgICAgICBzbSA9"
    "IHsic2Ftc3VuZyI6IuyCvOyEseyghOyekCIsInNrIGh5bml4IjoiU0vtlZjsnbTri4nsiqQiLCJh"
    "cHBsZSI6IuyVoO2UjCDso7zqsIAiLCJudmlkaWEiOiLsl5TruYTrlJTslYQg7KO86rCAIiwKICAg"
    "ICAgICAgICAgICAidGVzbGEiOiLthYzsiqzrnbwg7KO86rCAIiwia29zcGkiOiLsvZTsiqTtlLwi"
    "LCJrb3NkYXEiOiLsvZTsiqTri6UiLCJuYXNkYXEiOiLrgpjsiqTri6UifQogICAgICAgIGsgPSBz"
    "ZWxmLl90cmFuc2xhdGVfa2V5d29yZChjb21wYW55LCBzbSkKICAgICAgICBpZiAi7KO86rCAIiBu"
    "b3QgaW4gayBhbmQgayBub3QgaW4gWyLsvZTsiqTtlLwiLCLsvZTsiqTri6UiLCLrgpjsiqTri6Ui"
    "XTogayArPSAiIOyjvOqwgCIKICAgICAgICByZXR1cm4gYXdhaXQgc2VsZi5fbmF2ZXJfc2VhcmNo"
    "KGssICJyZWFkIHN0b2NrIHByaWNlLCBjaGFuZ2UsIG1hcmtldCBjYXAuIFJlc3BvbmQgaW4gS29y"
    "ZWFuLiIsIF9fZXZlbnRfZW1pdHRlcl9fKQoKICAgIGFzeW5jIGRlZiBjaGVja19uZXdzKHNlbGYs"
    "IHRvcGljOiBzdHIgPSAiIiwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiQ2hl"
    "Y2sgdG9kYXkncyB0b3AgbmV3cyBoZWFkbGluZXMgZnJvbSBOYXZlciBOZXdzLiBPcHRpb25hbGx5"
    "IGZpbHRlciBieSB0b3BpYy4KICAgICAgICA6cGFyYW0gdG9waWM6IOuJtOyKpCDso7zsoJwgKOyY"
    "iDog6rK97KCcLCDsiqTtj6zsuKAsIElULCDrtoDsgrApLiDruYTsm4zrkZDrqbQg7Jik64qY7J2Y"
    "IOyjvOyalCDribTsiqQg7KCE7LK0LgogICAgICAgICIiIgogICAgICAgIHRwID0gKHRvcGljIG9y"
    "ICIiKS5zdHJpcCgpCiAgICAgICAgY2FjaGVfa2V5ID0gIm5ld3M6IiArICh0cCBvciAidG9kYXki"
    "KQogICAgICAgIGNhY2hlZCA9IHNlbGYuX2dldF9jYWNoZShjYWNoZV9rZXkpCiAgICAgICAgaWYg"
    "Y2FjaGVkOiByZXR1cm4gY2FjaGVkCiAgICAgICAgcXVlcnkgPSAodHAgKyAiIOuJtOyKpCIpIGlm"
    "IHRwIGVsc2UgIuyYpOuKmCDso7zsmpQg64m07IqkIgogICAgICAgIHJlc3VsdCA9IGF3YWl0IHNl"
    "bGYuX2FwaV9zZWFyY2gocXVlcnksIGtpbmQ9Im5ld3MiLCBkaXNwbGF5PTUsIF9fZXZlbnRfZW1p"
    "dHRlcl9fPV9fZXZlbnRfZW1pdHRlcl9fKQogICAgICAgIHNlbGYuX3NldF9jYWNoZShjYWNoZV9r"
    "ZXksIHJlc3VsdCkKICAgICAgICByZXR1cm4gcmVzdWx0CgogICAgYXN5bmMgZGVmIGNoZWNrX2V4"
    "Y2hhbmdlX3JhdGUoc2VsZiwgY3VycmVuY3k6IHN0ciA9ICJkb2xsYXIiLCBfX2V2ZW50X2VtaXR0"
    "ZXJfXz1Ob25lKToKICAgICAgICAiIiJDaGVjayBjdXJyZW50IGV4Y2hhbmdlIHJhdGVzLgogICAg"
    "ICAgIDpwYXJhbSBjdXJyZW5jeTogQ3VycmVuY3kgbmFtZSAoZG9sbGFyLCB5ZW4sIGV1cm8sIHl1"
    "YW4pCiAgICAgICAgIiIiCiAgICAgICAgcm0gPSB7ImRvbGxhciI6IuuLrOufrCDtmZjsnKgiLCJ1"
    "c2QiOiLri6zrn6wg7ZmY7JyoIiwieWVuIjoi7JeU7ZmUIO2ZmOycqCIsImV1cm8iOiLsnKDroZwg"
    "7ZmY7JyoIiwieXVhbiI6IuychOyViCDtmZjsnKgiLCJwb3VuZCI6Iu2MjOyatOuTnCDtmZjsnKgi"
    "fQogICAgICAgIHJldHVybiBhd2FpdCBzZWxmLl9uYXZlcl9zZWFyY2goc2VsZi5fdHJhbnNsYXRl"
    "X2tleXdvcmQoY3VycmVuY3ksIHJtKSwKICAgICAgICAgICAgInJlYWQgZXhjaGFuZ2UgcmF0ZSwg"
    "Y2hhbmdlIGZyb20geWVzdGVyZGF5LiBSZXNwb25kIGluIEtvcmVhbi4iLCBfX2V2ZW50X2VtaXR0"
    "ZXJfXykKCiAgICBhc3luYyBkZWYgY2hlY2tfc3BvcnRzKHNlbGYsIHNwb3J0OiBzdHIgPSAic29j"
    "Y2VyIiwgX19ldmVudF9lbWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIiQ2hlY2sgc3BvcnRzIHNj"
    "b3JlcyBhbmQgcmVzdWx0cy4KICAgICAgICA6cGFyYW0gc3BvcnQ6IFNwb3J0IHR5cGUgKHNvY2Nl"
    "ciwgYmFzZWJhbGwsIGJhc2tldGJhbGwsIGtibywgZXBsKQogICAgICAgICIiIgogICAgICAgIHNt"
    "ID0geyJzb2NjZXIiOiLstpXqtawg6rK96riw6rKw6rO8IiwiYmFzZWJhbGwiOiLslbzqtawg6rK9"
    "6riw6rKw6rO8IiwiYmFza2V0YmFsbCI6IuuGjeq1rCDqsr3quLDqsrDqs7wiLAogICAgICAgICAg"
    "ICAgICJrYm8iOiJLQk8g6rK96riw6rKw6rO8IiwiZXBsIjoiRVBMIOqysOqzvCIsIm5iYSI6Ik5C"
    "QSDqsrDqs7wifQogICAgICAgIHJldHVybiBhd2FpdCBzZWxmLl9uYXZlcl9zZWFyY2goc2VsZi5f"
    "dHJhbnNsYXRlX2tleXdvcmQoc3BvcnQsIHNtKSwKICAgICAgICAgICAgInJlYWQgcmVjZW50IG1h"
    "dGNoIHJlc3VsdHMsIHNjb3Jlcywgc3RhbmRpbmdzLiBSZXNwb25kIGluIEtvcmVhbi4iLCBfX2V2"
    "ZW50X2VtaXR0ZXJfXykKCiAgICBhc3luYyBkZWYgc3VtbWFyaXplX3lvdXR1YmUoc2VsZiwgdXJs"
    "OiBzdHIsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIlN1bW1hcml6ZSBhIFlv"
    "dVR1YmUgdmlkZW8uCiAgICAgICAgOnBhcmFtIHVybDogWW91VHViZSBVUkwKICAgICAgICAiIiIK"
    "ICAgICAgICBpZiAieW91dHViZS5jb20iIG5vdCBpbiB1cmwgYW5kICJ5b3V0dS5iZSIgbm90IGlu"
    "IHVybDogcmV0dXJuICJZb3VUdWJlIFVSTOydtCDslYTri5nri4jri6QuIgogICAgICAgIHJldHVy"
    "biBhd2FpdCBzZWxmLmJyb3dzZSh1cmwgKyAiIHN1bW1hcml6ZSB2aWRlbyB0aXRsZSwgY2hhbm5l"
    "bCwgdmlldyBjb3VudCwgbWFpbiBjb250ZW50IGluIEtvcmVhbi4iLCBfX2V2ZW50X2VtaXR0ZXJf"
    "XykKCiAgICBhc3luYyBkZWYgb3Blbl9hbmRfc3VtbWFyaXplKHNlbGYsIHVybDogc3RyLCBfX2V2"
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
    "bWl0dGVyX18pCgogICAgYXN5bmMgZGVmIG11bHRpX2FnZW50X2Jyb3dzZShzZWxmLCB0YXNrOiBz"
    "dHIsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUsIF9fdXNlcl9fPXt9KToKICAgICAgICAiIiJNdWx0"
    "aS1BZ2VudCDrqqjrk5zroZwg67O17J6h7ZWcIOyekeyXhSDsiJjtlokuCiAgICAgICAgOnBhcmFt"
    "IHRhc2s6IOyekeyXhSDrgrTsmqkKICAgICAgICAiIiIKICAgICAgICBhc3luYyBkZWYgZW1pdCht"
    "c2csIGRvbmU9RmFsc2UpOgogICAgICAgICAgICBpZiBfX2V2ZW50X2VtaXR0ZXJfXzogYXdhaXQg"
    "X19ldmVudF9lbWl0dGVyX18oeyJ0eXBlIjoic3RhdHVzIiwiZGF0YSI6eyJkZXNjcmlwdGlvbiI6"
    "bXNnLCJkb25lIjpkb25lfX0pCiAgICAgICAgYXdhaXQgZW1pdCgiTXVsdGktQWdlbnQg7KGw7IKs"
    "IOyLnOyekS4uLiIpCiAgICAgICAgdHJ5OgogICAgICAgICAgICByZXN1bHQgPSBhd2FpdCBzZWxm"
    "Ll9wb3N0KCIvYnJvd3NlL211bHRpIiwgeyJ0YXNrIjogdGFza30pCiAgICAgICAgICAgIGF3YWl0"
    "IGVtaXQoIuyZhOujjCIsIGRvbmU9VHJ1ZSkKICAgICAgICAgICAgcmV0dXJuIHJlc3VsdC5nZXQo"
    "InN1bW1hcnkiLCByZXN1bHQuZ2V0KCJyZXN1bHQiLCBzdHIocmVzdWx0KSkpCiAgICAgICAgZXhj"
    "ZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgICAgICBhd2FpdCBlbWl0KCLsmKTrpZgiLCBkb25l"
    "PVRydWUpCiAgICAgICAgICAgIHJldHVybiAiTXVsdGktQWdlbnQg7Jik66WYOiAiICsgc3RyKGUp"
    "CgogICAgYXN5bmMgZGVmIGNsb3NlX2Jyb3dzZXIoc2VsZiwgX19ldmVudF9lbWl0dGVyX189Tm9u"
    "ZSk6CiAgICAgICAgIiIiQ2xvc2UgYnJvd3NlciBzZXNzaW9uIGFuZCBjbGVhciBjYWNoZS4iIiIK"
    "ICAgICAgICBzZWxmLl9zZXNzaW9uX2lkID0gTm9uZQogICAgICAgIHNlbGYuX2NhY2hlLmNsZWFy"
    "KCkKICAgICAgICByZXR1cm4gIuu4jOudvOyasOyggCDshLjshZgg7KKF66OMICsg7LqQ7IucIOy0"
    "iOq4sO2ZlCDsmYTro4wiCgogICAgYXN5bmMgZGVmIGdldF9tZW1vcnkoc2VsZiwgX19ldmVudF9l"
    "bWl0dGVyX189Tm9uZSk6CiAgICAgICAgIiIi7KCA7J6l65CcIOyCrOyaqeyekCDsoJXrs7Qg7KGw"
    "7ZqMLiIiIgogICAgICAgIGlmIG5vdCBzZWxmLnZhbHZlcy5FTkFCTEVfTUVNT1JZOiByZXR1cm4g"
    "IuuplOuqqOumrCDruYTtmZzshLHtmZQiCiAgICAgICAgdHJ5OgogICAgICAgICAgICBpbXBvcnQg"
    "aHR0cHgsIGpzb24KICAgICAgICAgICAgYXN5bmMgd2l0aCBodHRweC5Bc3luY0NsaWVudCh0aW1l"
    "b3V0PTEwKSBhcyBjOgogICAgICAgICAgICAgICAgciA9IGF3YWl0IGMuZ2V0KHNlbGYudmFsdmVz"
    "LkJST1dTRVJfQUdFTlRfVVJMICsgIi9tZW1vcnkiLCBoZWFkZXJzPXNlbGYuX2hlYWRlcnMoKSkK"
    "ICAgICAgICAgICAgICAgIHJldHVybiAi8J+TnSDrqZTrqqjrpqw6XG4iICsganNvbi5kdW1wcyhy"
    "Lmpzb24oKSwgZW5zdXJlX2FzY2lpPUZhbHNlLCBpbmRlbnQ9MikKICAgICAgICBleGNlcHQgRXhj"
    "ZXB0aW9uIGFzIGU6IHJldHVybiAi66mU66qo66asIOyhsO2ajCDsi6TtjKg6ICIgKyBzdHIoZSkK"
    "CiAgICBhc3luYyBkZWYgdXBkYXRlX21lbW9yeShzZWxmLCBpbmZvOiBzdHIsIF9fZXZlbnRfZW1p"
    "dHRlcl9fPU5vbmUpOgogICAgICAgICIiIuyCrOyaqeyekCDsoJXrs7Qg7KCA7J6lLgogICAgICAg"
    "IDpwYXJhbSBpbmZvOiDquLDslrXtlaAg7KCV67O0CiAgICAgICAgIiIiCiAgICAgICAgaWYgbm90"
    "IHNlbGYudmFsdmVzLkVOQUJMRV9NRU1PUlk6IHJldHVybiAi66mU66qo66asIOu5hO2ZnOyEse2Z"
    "lCIKICAgICAgICBib2R5ID0geyJmYWN0cyI6IFtpbmZvWzoyMDBdXX0KICAgICAgICBmb3IgbG9j"
    "IGluIFsi7ISc7Jq4Iiwi67aA7IKwIiwi64yA6rWsIiwi7J247LKcIiwi6rSR7KO8Iiwi64yA7KCE"
    "Iiwi7Jq47IKwIiwi7KCc7KO8Il06CiAgICAgICAgICAgIGlmIGxvYyBpbiBpbmZvOiBib2R5WyJs"
    "b2NhdGlvbiJdID0gbG9jOyBicmVhawogICAgICAgIHRyeToKICAgICAgICAgICAgYXdhaXQgc2Vs"
    "Zi5fcG9zdCgiL21lbW9yeSIsIGJvZHkpOyByZXR1cm4gIuKchSDquLDslrXtlojsirXri4jri6Q6"
    "ICIgKyBpbmZvCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOiByZXR1cm4gIuyggOyepSDs"
    "i6TtjKg6ICIgKyBzdHIoZSkKCiAgICBhc3luYyBkZWYgY2xlYXJfbWVtb3J5KHNlbGYsIF9fZXZl"
    "bnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIuyggOyepeuQnCDrqqjrk6Ag66mU66qo66as"
    "IOyCreygnC4iIiIKICAgICAgICB0cnk6CiAgICAgICAgICAgIGltcG9ydCBodHRweAogICAgICAg"
    "ICAgICBhc3luYyB3aXRoIGh0dHB4LkFzeW5jQ2xpZW50KHRpbWVvdXQ9MTApIGFzIGM6CiAgICAg"
    "ICAgICAgICAgICBhd2FpdCBjLmRlbGV0ZShzZWxmLnZhbHZlcy5CUk9XU0VSX0FHRU5UX1VSTCAr"
    "ICIvbWVtb3J5IiwgaGVhZGVycz1zZWxmLl9oZWFkZXJzKCkpCiAgICAgICAgICAgICAgICByZXR1"
    "cm4gIuKchSDrqZTrqqjrpqwg7LSI6riw7ZmUIOyZhOujjCIKICAgICAgICBleGNlcHQgRXhjZXB0"
    "aW9uIGFzIGU6IHJldHVybiAi7IKt7KCcIOyLpO2MqDogIiArIHN0cihlKQoKICAgIGFzeW5jIGRl"
    "ZiBsaXN0X2ZpbGVzKHNlbGYsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIn4v"
    "YWktc2hhcmUg7Y+0642U7J2YIO2MjOydvCDrqqnroZ0g7KGw7ZqMLiIiIgogICAgICAgIGlmIG5v"
    "dCBzZWxmLnZhbHZlcy5FTkFCTEVfRklMRV9BQ0NFU1M6IHJldHVybiAi7YyM7J28IOygkeq3vCDr"
    "uYTtmZzshLHtmZQiCiAgICAgICAgdHJ5OgogICAgICAgICAgICBpbXBvcnQgaHR0cHgKICAgICAg"
    "ICAgICAgYXN5bmMgd2l0aCBodHRweC5Bc3luY0NsaWVudCh0aW1lb3V0PTEwKSBhcyBjOgogICAg"
    "ICAgICAgICAgICAgciA9IGF3YWl0IGMuZ2V0KHNlbGYudmFsdmVzLkJST1dTRVJfQUdFTlRfVVJM"
    "ICsgIi9maWxlcyIsIGhlYWRlcnM9c2VsZi5faGVhZGVycygpKQogICAgICAgICAgICAgICAgZmls"
    "ZXMgPSByLmpzb24oKS5nZXQoImZpbGVzIiwgW10pCiAgICAgICAgICAgICAgICBpZiBub3QgZmls"
    "ZXM6IHJldHVybiAi8J+TgSDtjIzsnbwg7JeG7J2MICh+L2FpLXNoYXJl7JeQIO2MjOydvOydhCDr"
    "hKPslrTso7zshLjsmpQpIgogICAgICAgICAgICAgICAgbGluZXMgPSBbIvCfk4Eg7YyM7J28IOuq"
    "qeuhnToiXQogICAgICAgICAgICAgICAgZm9yIGYgaW4gZmlsZXM6CiAgICAgICAgICAgICAgICAg"
    "ICAgbGluZXMuYXBwZW5kKCIgIOKAoiAiICsgZlsibmFtZSJdICsgIiAoIiArIHN0cihyb3VuZChm"
    "WyJzaXplIl0vMTAyNCwgMSkpICsgIktCKSIpCiAgICAgICAgICAgICAgICByZXR1cm4gIlxuIi5q"
    "b2luKGxpbmVzKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZTogcmV0dXJuICLsobDtmowg"
    "7Iuk7YyoOiAiICsgc3RyKGUpCgogICAgYXN5bmMgZGVmIHJlYWRfZmlsZShzZWxmLCBmaWxlbmFt"
    "ZTogc3RyLCBfX2V2ZW50X2VtaXR0ZXJfXz1Ob25lKToKICAgICAgICAiIiLroZzsu6wg7YyM7J28"
    "IOydveq4sC4KICAgICAgICA6cGFyYW0gZmlsZW5hbWU6IO2MjOydvOuqhQogICAgICAgICIiIgog"
    "ICAgICAgIGlmIG5vdCBzZWxmLnZhbHZlcy5FTkFCTEVfRklMRV9BQ0NFU1M6IHJldHVybiAi7YyM"
    "7J28IOygkeq3vCDruYTtmZzshLHtmZQiCiAgICAgICAgdHJ5OgogICAgICAgICAgICBpbXBvcnQg"
    "aHR0cHgKICAgICAgICAgICAgYXN5bmMgd2l0aCBodHRweC5Bc3luY0NsaWVudCh0aW1lb3V0PTMw"
    "KSBhcyBjOgogICAgICAgICAgICAgICAgciA9IGF3YWl0IGMuZ2V0KHNlbGYudmFsdmVzLkJST1dT"
    "RVJfQUdFTlRfVVJMICsgIi9maWxlcy8iICsgZmlsZW5hbWUsIGhlYWRlcnM9c2VsZi5faGVhZGVy"
    "cygpKQogICAgICAgICAgICAgICAgaWYgci5zdGF0dXNfY29kZSA9PSA0MDQ6IHJldHVybiAi4p2M"
    "IO2MjOydvCDsl4bsnYw6ICIgKyBmaWxlbmFtZQogICAgICAgICAgICAgICAgcmV0dXJuICLwn5OE"
    "ICIgKyBmaWxlbmFtZSArICI6XG4iICsgci5qc29uKCkuZ2V0KCJjb250ZW50IiwgIiIpWzo1MDAw"
    "XQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZTogcmV0dXJuICLsnb3quLAg7Iuk7YyoOiAi"
    "ICsgc3RyKGUpCgogICAgYXN5bmMgZGVmIHNhdmVfZmlsZShzZWxmLCBmaWxlbmFtZTogc3RyLCBj"
    "b250ZW50OiBzdHIsIF9fZXZlbnRfZW1pdHRlcl9fPU5vbmUpOgogICAgICAgICIiIuuhnOy7rCDt"
    "jIzsnbwg7KCA7J6lLgogICAgICAgIDpwYXJhbSBmaWxlbmFtZTog7YyM7J2866qFCiAgICAgICAg"
    "OnBhcmFtIGNvbnRlbnQ6IOyggOyepe2VoCDrgrTsmqkKICAgICAgICAiIiIKICAgICAgICBpZiBu"
    "b3Qgc2VsZi52YWx2ZXMuRU5BQkxFX0ZJTEVfQUNDRVNTOiByZXR1cm4gIu2MjOydvCDsoJHqt7wg"
    "67mE7Zmc7ISx7ZmUIgogICAgICAgIHRyeToKICAgICAgICAgICAgaW1wb3J0IGh0dHB4CiAgICAg"
    "ICAgICAgIGFzeW5jIHdpdGggaHR0cHguQXN5bmNDbGllbnQodGltZW91dD0zMCkgYXMgYzoKICAg"
    "ICAgICAgICAgICAgIHIgPSBhd2FpdCBjLnBvc3Qoc2VsZi52YWx2ZXMuQlJPV1NFUl9BR0VOVF9V"
    "UkwgKyAiL2ZpbGVzLyIgKyBmaWxlbmFtZSwganNvbj17ImNvbnRlbnQiOmNvbnRlbnR9LCBoZWFk"
    "ZXJzPXNlbGYuX2hlYWRlcnMoKSkKICAgICAgICAgICAgICAgIGQgPSByLmpzb24oKQogICAgICAg"
    "ICAgICAgICAgaWYgZC5nZXQoInN1Y2Nlc3MiKTogcmV0dXJuICLinIUg7KCA7J6lOiAiICsgZmls"
    "ZW5hbWUgKyAiICgiICsgc3RyKGQuZ2V0KCJzaXplIiwwKSkgKyAiQikiCiAgICAgICAgICAgICAg"
    "ICByZXR1cm4gIuKdjCDsi6TtjKg6ICIgKyBzdHIoZCkKICAgICAgICBleGNlcHQgRXhjZXB0aW9u"
    "IGFzIGU6IHJldHVybiAi7KCA7J6lIOyLpO2MqDogIiArIHN0cihlKQoKICAgIGFzeW5jIGRlZiBj"
    "b21wYXJlX3NpdGVzKHNlbGYsIHRhc2s6IHN0ciwgdXJsczogc3RyID0gIiIsIF9fZXZlbnRfZW1p"
    "dHRlcl9fPU5vbmUpOgogICAgICAgICIiIuyXrOufrCDsgqzsnbTtirgg67mE6rWQIOu2hOyEnSAo"
    "7Jyg66OMIEFQSSDqtozsnqUpLgogICAgICAgIDpwYXJhbSB0YXNrOiDruYTqtZAg64K07JqpCiAg"
    "ICAgICAgOnBhcmFtIHVybHM6IFVSTOuTpCDsibztkZwg6rWs67aEICjruYTsm4zrkZDrqbQg7J6Q"
    "64+ZKQogICAgICAgICIiIgogICAgICAgIGlmIG5vdCBzZWxmLnZhbHZlcy5FTkFCTEVfTVVMVElU"
    "QUI6IHJldHVybiAi66mA7Yuw7YOtIOu5hO2ZnOyEse2ZlCIKICAgICAgICBpZiBfX2V2ZW50X2Vt"
    "aXR0ZXJfXzogYXdhaXQgX19ldmVudF9lbWl0dGVyX18oeyJ0eXBlIjoic3RhdHVzIiwiZGF0YSI6"
    "eyJkZXNjcmlwdGlvbiI6IuupgO2LsO2DrSDruYTqtZAg7Iuc7J6RLi4uIiwiZG9uZSI6RmFsc2V9"
    "fSkKICAgICAgICB1cmxfbGlzdCA9IFt1LnN0cmlwKCkgZm9yIHUgaW4gdXJscy5zcGxpdCgiLCIp"
    "IGlmIHUuc3RyaXAoKV1bOnNlbGYudmFsdmVzLk1BWF9UQUJTXSBpZiB1cmxzIGVsc2UgW10KICAg"
    "ICAgICB0cnk6CiAgICAgICAgICAgIGltcG9ydCBodHRweAogICAgICAgICAgICBib2R5ID0geyJ0"
    "YXNrIjp0YXNrLCJ1cmxzIjp1cmxfbGlzdCwibWF4X3N0ZXBzX3Blcl90YWIiOjh9CiAgICAgICAg"
    "ICAgIGlmIHNlbGYudmFsdmVzLkxMTV9QUk9WSURFUjogYm9keVsicHJvdmlkZXIiXSA9IHNlbGYu"
    "dmFsdmVzLkxMTV9QUk9WSURFUgogICAgICAgICAgICBpZiBzZWxmLnZhbHZlcy5MTE1fQVBJX0tF"
    "WTogYm9keVsiYXBpX2tleSJdID0gc2VsZi52YWx2ZXMuTExNX0FQSV9LRVkKICAgICAgICAgICAg"
    "aWYgc2VsZi52YWx2ZXMuTExNX01PREVMOiBib2R5WyJtb2RlbCJdID0gc2VsZi52YWx2ZXMuTExN"
    "X01PREVMCiAgICAgICAgICAgIGFzeW5jIHdpdGggaHR0cHguQXN5bmNDbGllbnQodGltZW91dD1z"
    "ZWxmLnZhbHZlcy5SRVFVRVNUX1RJTUVPVVQpIGFzIGM6CiAgICAgICAgICAgICAgICByID0gYXdh"
    "aXQgYy5wb3N0KHNlbGYudmFsdmVzLkJST1dTRVJfQUdFTlRfVVJMICsgIi9icm93c2UvbXVsdGl0"
    "YWIiLCBqc29uPWJvZHksIGhlYWRlcnM9c2VsZi5faGVhZGVycygpKQogICAgICAgICAgICAgICAg"
    "ZGF0YSA9IHIuanNvbigpCiAgICAgICAgICAgIGlmIF9fZXZlbnRfZW1pdHRlcl9fOiBhd2FpdCBf"
    "X2V2ZW50X2VtaXR0ZXJfXyh7InR5cGUiOiJzdGF0dXMiLCJkYXRhIjp7ImRlc2NyaXB0aW9uIjoi"
    "7JmE66OMIiwiZG9uZSI6VHJ1ZX19KQogICAgICAgICAgICBpZiBkYXRhLmdldCgic3VjY2VzcyIp"
    "OgogICAgICAgICAgICAgICAgdGFicyA9IGRhdGEuZ2V0KCJ0YWJzIixbXSkKICAgICAgICAgICAg"
    "ICAgIHNvdXJjZXMgPSAiXG4iLmpvaW4oWyIgIOKAoiDtg60iICsgc3RyKHRbInRhYiJdKSArICI6"
    "ICIgKyB0WyJ1cmwiXSBmb3IgdCBpbiB0YWJzXSkKICAgICAgICAgICAgICAgIHJldHVybiBkYXRh"
    "LmdldCgic3VtbWFyeSIsIiIpICsgIlxuXG7wn5ORIOywuOyhsDpcbiIgKyBzb3VyY2VzCiAgICAg"
    "ICAgICAgIHJldHVybiAi7Iuk7YyoOiAiICsgZGF0YS5nZXQoImVycm9yIiwiIikKICAgICAgICBl"
    "eGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAgICAgICAgICAgIGlmIF9fZXZlbnRfZW1pdHRlcl9fOiBh"
    "d2FpdCBfX2V2ZW50X2VtaXR0ZXJfXyh7InR5cGUiOiJzdGF0dXMiLCJkYXRhIjp7ImRlc2NyaXB0"
    "aW9uIjoi7Iuk7YyoIiwiZG9uZSI6VHJ1ZX19KQogICAgICAgICAgICByZXR1cm4gIuupgO2LsO2D"
    "rSDsmKTrpZg6ICIgKyBzdHIoZSkK"
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

TARGET = '    def _translate_keyword(self, keyword: str, keyword_map: dict) -> str:'
if TARGET in code:
    code = code.replace(TARGET, WIKI_HELPER + TARGET)
    print("  ✅ 패치 2: _is_encyclopedic_query() + _smart_search() 헬퍼 추가됨")
else:
    print("  ⚠️  패치 2: _translate_keyword 위치 불일치 — 수동 확인 필요")

# ── 패치 3: search_wikipedia() Tool 신규 추가 ───────────────────────────
# search_naver() 바로 다음에 삽입
WIKI_TOOL = '''
    async def search_wikipedia(self, keyword: str, __event_emitter__=None):
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
      - TAVILY_API_KEY=${{TAVILY_API_KEY:-}}
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
