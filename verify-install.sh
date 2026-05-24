#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  설치 검증 스크립트 — verify-install.sh  v4.0.0                     ║
# ║  3개 설치 스크립트 전체 대조 검증                                    ║
# ║                                                                      ║
# ║  검증 대상:                                                          ║
# ║  - Phase 2: start-openwebui-hardened.sh (v1.1.0)                   ║
# ║  - Phase 3: setup-telegram-openwebui-bridge-hardened.sh (v1.4.0)   ║
# ║  - Browser: setup-browser-agent-browser-use-v6.sh (v6.4.0)       ║
# ║                                                                      ║
# ║  v4.0.0 변경사항 (v3.0.0 대비):                                    ║
# ║  - secrets/data 디렉토리 sudo 권한 체크 수정 (uid 1001 소유 대응)  ║
# ║  - browser-agent 헬스체크 curl→python3 변경 (curl 미설치 대응)     ║
# ║  - telegram 헬스체크 curl→python3 변경                             ║
# ║  - 헬스 실패 시 docker inspect health 대체 판정                    ║
# ║  - 읽기 전용: chmod 자동 수정 제거 (보고만, 시스템 변경 없음)      ║
# ║  v4.0.0: head() 함수명 충돌 수정 (── -1 ── 표시 버그 해결)         ║
# ║  v4.0.0: unhealthy 컨테이너 ⚠️ 경고 표시 (기존 ✅→⚠️)              ║
# ║  - Phase 2 누락 디렉토리 18개 추가 (secrets, logs 등)              ║
# ║  - Phase 2 누락 파일 22개 추가 (Python 모듈, secrets, 보안 파일)   ║
# ║  - Phase 3 secrets 디렉토리 + 4개 Secret 파일 추가                 ║
# ║  - 데이터 파일(contacts/history/schedules) → 선택 항목으로 변경    ║
# ║  - Qdrant / Telegram 헬스체크 추가                                 ║
# ║  - OpenWebUI secrets chmod 700 검증 추가                           ║
# ║  - Nginx 설정 / 감사 로그 / Cloudflare Tunnel 검증 추가           ║
# ║  - Phase 라벨 정정 (Phase1→Phase2, Browser Agent 별도)             ║
# ║  - multi_agent 디렉토리 (8개 파일) 검증 추가                      ║
# ╚══════════════════════════════════════════════════════════════════════╝
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'
B='\033[1m'; N='\033[0m'
ok()   { echo -e "${G}  ✅  $*${N}"; }
warn() { echo -e "${Y}  ⚠️   $*${N}"; }
fail() { echo -e "${R}  ❌  $*${N}"; ((FAIL_COUNT++)); }
info() { echo -e "${C}  ℹ️   $*${N}"; }
section() { echo -e "\n${B}── $* ──${N}"; }

FAIL_COUNT=0
OWUI_DIR="${HOME}/OpenWebUI"
TELEGRAM_DIR="${HOME}/telegram-openwebui-bridge"

echo -e "${B}"
cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════════╗
║  OpenWebUI AI 에이전트 — 전체 설치 검증 v4.0.0                      ║
║  Phase 2 + Phase 3 + Browser Agent v6.4 완전 대조                   ║
║  ※ secrets/data 확인에 sudo 사용 (uid 1001 소유 대응)              ║
╚══════════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${N}"

# ════════════════════════════════
# 1. 디렉토리 구조
# ════════════════════════════════
section "1. 디렉토리 구조 확인 (25개)"

declare -a DIR_LIST=(
  # ── Phase 2: start-openwebui-hardened.sh ──
  "Phase2|OpenWebUI 루트|${OWUI_DIR}"
  "Phase2|tools-api|${OWUI_DIR}/tools-api"
  "Phase2|tools-api/data|${OWUI_DIR}/tools-api/data"
  "Phase2|twilio-bot|${OWUI_DIR}/twilio-bot"
  "Phase2|twilio-bot/data|${OWUI_DIR}/twilio-bot/data"
  "Phase2|twilio-bot/data/recordings|${OWUI_DIR}/twilio-bot/data/recordings"
  "Phase2|twilio-bot/data/reports|${OWUI_DIR}/twilio-bot/data/reports"
  "Phase2|secrets (Docker Secrets)|${OWUI_DIR}/secrets"
  "Phase2|logs/twilio-bot|${OWUI_DIR}/logs/twilio-bot"
  "Phase2|logs/openapi-tools|${OWUI_DIR}/logs/openapi-tools"
  "Phase2|logs/nginx|${OWUI_DIR}/logs/nginx"
  # ── Phase 3: setup-telegram-openwebui-bridge-hardened.sh ──
  "Phase3|telegram-bridge 루트|${TELEGRAM_DIR}"
  "Phase3|telegram-bridge/bot|${TELEGRAM_DIR}/bot"
  "Phase3|telegram-bridge/data|${TELEGRAM_DIR}/data"
  "Phase3|telegram-bridge/logs|${TELEGRAM_DIR}/logs"
  "Phase3|telegram-bridge/secrets|${TELEGRAM_DIR}/secrets"
  # ── Browser Agent: setup-browser-agent-browser-use-v6.sh ──
  "Browser|browser-agent|${OWUI_DIR}/browser-agent"
  "Browser|browser-agent/data|${OWUI_DIR}/browser-agent/data"
  "Browser|browser-agent/data/screenshots|${OWUI_DIR}/browser-agent/data/screenshots"
  "Browser|browser-agent/data/sessions|${OWUI_DIR}/browser-agent/data/sessions"
  "Browser|browser-agent/data/results|${OWUI_DIR}/browser-agent/data/results"
  "Browser|browser-agent/data/audit|${OWUI_DIR}/browser-agent/data/audit"
  "Browser|browser-agent/secrets|${OWUI_DIR}/browser-agent/secrets"
  "Browser|browser-agent/multi_agent|${OWUI_DIR}/browser-agent/multi_agent"
  "Browser|ai-share (로컬 파일 공유)|${HOME}/ai-share"
)

for ENTRY in "${DIR_LIST[@]}"; do
  IFS='|' read -r PHASE LABEL DIR <<< "$ENTRY"
  # secrets, data 디렉토리는 uid 1001 소유 → sudo로 확인
  if [ -d "$DIR" ] || sudo test -d "$DIR" 2>/dev/null; then
    PERM=$(sudo stat -c "%a" "$DIR" 2>/dev/null || stat -c "%a" "$DIR" 2>/dev/null || echo "???")
    ok "[${PHASE}] ${LABEL} [${PERM}]"
  else
    fail "[${PHASE}] ${LABEL} 없음: ${DIR##$HOME/}"
  fi
done

# ════════════════════════════════
# 2. 필수 파일 확인
# ════════════════════════════════
section "2. 필수 파일 확인 (38개)"

declare -a FILE_LIST=(
  # ── Phase 2: docker-compose + 환경설정 ──
  "Phase2|.env|${OWUI_DIR}/.env"
  "Phase2|docker-compose.yml|${OWUI_DIR}/docker-compose.yml"
  "Phase2|docker-compose.override.yml|${OWUI_DIR}/docker-compose.override.yml"
  "Phase2|.gitignore|${OWUI_DIR}/.gitignore"
  "Phase2|.dockerignore|${OWUI_DIR}/.dockerignore"
  "Phase2|view-audit-log.sh|${OWUI_DIR}/view-audit-log.sh"
  # ── Phase 2: tools-api ──
  "Phase2|tools-api/main.py|${OWUI_DIR}/tools-api/main.py"
  "Phase2|tools-api/Dockerfile|${OWUI_DIR}/tools-api/Dockerfile"
  "Phase2|tools-api/requirements.txt|${OWUI_DIR}/tools-api/requirements.txt"
  # ── Phase 2: twilio-bot ──
  "Phase2|twilio-bot/twilio_bot.py|${OWUI_DIR}/twilio-bot/twilio_bot.py"
  "Phase2|twilio-bot/ai_config.py|${OWUI_DIR}/twilio-bot/ai_config.py"
  "Phase2|twilio-bot/scheduler.py|${OWUI_DIR}/twilio-bot/scheduler.py"
  "Phase2|twilio-bot/call_history.py|${OWUI_DIR}/twilio-bot/call_history.py"
  "Phase2|twilio-bot/entrypoint.sh|${OWUI_DIR}/twilio-bot/entrypoint.sh"
  "Phase2|twilio-bot/Dockerfile|${OWUI_DIR}/twilio-bot/Dockerfile"
  "Phase2|twilio-bot/requirements.txt|${OWUI_DIR}/twilio-bot/requirements.txt"
  # ── Phase 2: Docker Secrets (6개 파일) ──
  "Phase2|secrets/twilio_auth_token|${OWUI_DIR}/secrets/twilio_auth_token"
  "Phase2|secrets/api_secret|${OWUI_DIR}/secrets/api_secret"
  "Phase2|secrets/groq_api_key|${OWUI_DIR}/secrets/groq_api_key"
  "Phase2|secrets/admin_pin|${OWUI_DIR}/secrets/admin_pin"
  "Phase2|secrets/webui_secret_key|${OWUI_DIR}/secrets/webui_secret_key"
  "Phase2|secrets/entrypoint-secrets.sh|${OWUI_DIR}/secrets/entrypoint-secrets.sh"
  # ── Phase 3: Telegram 브릿지 ──
  "Phase3|.env|${TELEGRAM_DIR}/.env"
  "Phase3|docker-compose.yml|${TELEGRAM_DIR}/docker-compose.yml"
  "Phase3|bot/Dockerfile|${TELEGRAM_DIR}/bot/Dockerfile"
  "Phase3|bot/requirements.txt|${TELEGRAM_DIR}/bot/requirements.txt"
  "Phase3|bot/telegram_bot.py|${TELEGRAM_DIR}/bot/telegram_bot.py"
  "Phase3|bot/entrypoint.sh|${TELEGRAM_DIR}/bot/entrypoint.sh"
  # ── Phase 3: Telegram Secrets (4개 파일) ──
  "Phase3|secrets/telegram_bot_token|${TELEGRAM_DIR}/secrets/telegram_bot_token"
  "Phase3|secrets/openwebui_api_key|${TELEGRAM_DIR}/secrets/openwebui_api_key"
  "Phase3|secrets/webhook_secret|${TELEGRAM_DIR}/secrets/webhook_secret"
  "Phase3|secrets/tg_admin_pin|${TELEGRAM_DIR}/secrets/tg_admin_pin"
  # ── Browser Agent ──
  "Browser|Dockerfile|${OWUI_DIR}/browser-agent/Dockerfile"
  "Browser|entrypoint.sh|${OWUI_DIR}/browser-agent/entrypoint.sh"
  "Browser|agent_server.py|${OWUI_DIR}/browser-agent/agent_server.py"
  "Browser|openwebui_tool.py|${OWUI_DIR}/browser-agent/openwebui_tool.py"
  "Browser|seccomp-browser.json|${OWUI_DIR}/browser-agent/seccomp-browser.json"
  "Browser|logrotate.conf|${OWUI_DIR}/browser-agent/logrotate.conf"
)

for ENTRY in "${FILE_LIST[@]}"; do
  IFS='|' read -r PHASE LABEL FILE <<< "$ENTRY"
  # secrets 디렉토리 내 파일은 uid 1001 소유 → sudo로 확인
  if [ -f "$FILE" ] || sudo test -f "$FILE" 2>/dev/null; then
    SIZE=$(sudo du -sh "$FILE" 2>/dev/null | cut -f1 || du -sh "$FILE" 2>/dev/null | cut -f1 || echo "?")
    ok "[${PHASE}] ${LABEL} [${SIZE}]"
  else
    fail "[${PHASE}] ${LABEL} 없음: ${FILE##$HOME/}"
  fi
done

# ── 선택 파일 (설치 직후에는 없을 수 있음 — warn만) ──
echo ""
info "선택 파일 확인 (데이터 파일 — 사용 시 자동 생성):"
for ENTRY in \
  "Phase2|twilio-bot/data/contacts.json|${OWUI_DIR}/twilio-bot/data/contacts.json" \
  "Phase2|twilio-bot/data/call_history.json|${OWUI_DIR}/twilio-bot/data/call_history.json" \
  "Phase2|twilio-bot/data/schedules.json|${OWUI_DIR}/twilio-bot/data/schedules.json"; do
  IFS='|' read -r PHASE LABEL FILE <<< "$ENTRY"
  if [ -f "$FILE" ] || sudo test -f "$FILE" 2>/dev/null; then
    SIZE=$(sudo du -sh "$FILE" 2>/dev/null | cut -f1 || du -sh "$FILE" 2>/dev/null | cut -f1 || echo "?")
    ok "[${PHASE}] ${LABEL} [${SIZE}]"
  else
    info "[${PHASE}] ${LABEL} 미생성 (정상 — 첫 사용 시 자동 생성)"
  fi
done

# ════════════════════════════════
# 3. 파일 권한 보안 확인
# ════════════════════════════════
section "3. 보안 권한 확인"

check_perm() {
  local FILE="$1" EXPECTED="$2" LABEL="$3"
  if [ ! -e "$FILE" ] && ! sudo test -e "$FILE" 2>/dev/null; then
    warn "${LABEL} 파일 없음 (건너뜀)"; return
  fi
  local ACTUAL
  ACTUAL=$(sudo stat -c "%a" "$FILE" 2>/dev/null || stat -c "%a" "$FILE" 2>/dev/null || echo "???")
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    ok "${LABEL}: ${ACTUAL} ✔"
  else
    warn "${LABEL}: ${ACTUAL} (권장: ${EXPECTED})"
    info "  → 수동 수정: sudo chmod ${EXPECTED} ${FILE}"
  fi
}

# .env 파일 (600)
check_perm "${OWUI_DIR}/.env"           600 "[Phase2] .env"
check_perm "${TELEGRAM_DIR}/.env"       600 "[Phase3] .env"

# secrets 디렉토리 (700)
check_perm "${OWUI_DIR}/secrets"                  700 "[Phase2] secrets 디렉토리"
check_perm "${TELEGRAM_DIR}/secrets"              700 "[Phase3] secrets 디렉토리"
check_perm "${OWUI_DIR}/browser-agent/secrets"    750 "[Browser] secrets 디렉토리"

# view-audit-log.sh 실행 권한
if [ -f "${OWUI_DIR}/view-audit-log.sh" ]; then
  if [ -x "${OWUI_DIR}/view-audit-log.sh" ]; then
    ok "[Phase2] view-audit-log.sh 실행 권한 ✔"
  else
    warn "[Phase2] view-audit-log.sh 실행 권한 없음"
    info "  → 수동 수정: chmod +x ${OWUI_DIR}/view-audit-log.sh"
  fi
fi

# .env 에 LLM API 키 확인
if [ -f "${OWUI_DIR}/.env" ]; then
  KEY_LEN=$(grep "BROWSER_AGENT_API_KEY" "${OWUI_DIR}/.env" 2>/dev/null | cut -d= -f2 | wc -c)
  if [ "$KEY_LEN" -gt 20 ]; then
    ok "BROWSER_AGENT_API_KEY 설정됨 (${KEY_LEN}자)"
  else
    info "BROWSER_AGENT_API_KEY 미설정 (Browser Agent 미설치 시 정상)"
  fi

  # 멀티프로바이더 API 키 확인
  for ENVKEY in "GROQ_API_KEY" "OPENAI_API_KEY" "ANTHROPIC_API_KEY" "GOOGLE_API_KEY"; do
    ENVVAL=$(grep "^${ENVKEY}" "${OWUI_DIR}/.env" 2>/dev/null | cut -d= -f2)
    if [ -n "$ENVVAL" ] && [ ${#ENVVAL} -gt 10 ]; then
      ok "${ENVKEY} 설정됨"
    else
      info "${ENVKEY} 미설정 (선택)"
    fi
  done

  # LLM_PROVIDER 확인
  LLM_PROV=$(grep "^LLM_PROVIDER" "${OWUI_DIR}/.env" 2>/dev/null | cut -d= -f2)
  if [ -n "$LLM_PROV" ]; then
    ok "LLM_PROVIDER: ${LLM_PROV}"
  else
    info "LLM_PROVIDER 미설정 (기본: groq)"
  fi
fi

# openwebui_tool.py 에 API 키 플레이스홀더 잔존 확인
if [ -f "${OWUI_DIR}/browser-agent/openwebui_tool.py" ]; then
  if grep -q "__BROWSER_API_KEY_PLACEHOLDER__" "${OWUI_DIR}/browser-agent/openwebui_tool.py"; then
    warn "openwebui_tool.py에 API 키 플레이스홀더가 남아있음 — 도구 재등록 필요"
  else
    ok "openwebui_tool.py API 키 설정 확인됨"
  fi
fi

# ════════════════════════════════
# 4. Docker 컨테이너 상태
# ════════════════════════════════
section "4. Docker 컨테이너 상태"

if ! command -v docker &>/dev/null; then
  warn "Docker 없음 — 컨테이너 확인 건너뜀"
else
  # 컨테이너명 목록 (소스코드 docker-compose.yml 기준)
  # Phase2: qdrant, openapi-tools, open-webui (프로젝트명 openwebui- 접두사)
  #         twilio-bot (container_name 지정)
  # Phase3: telegram-openwebui-bridge (container_name 지정)
  # Browser: browser-agent (container_name 지정)
  for CNAME in \
    "openwebui-qdrant-1|Phase2|Qdrant 벡터DB" \
    "openwebui-openapi-tools-1|Phase2|OpenAPI Tools Server" \
    "openwebui-open-webui-1|Phase2|Open WebUI" \
    "twilio-bot|Phase2|Twilio AI 전화봇" \
    "telegram-openwebui-bridge|Phase3|Telegram 브릿지" \
    "browser-agent|Browser|브라우저 에이전트"; do
    IFS='|' read -r NAME PHASE DESC <<< "$CNAME"
    STATUS=$(docker inspect --format='{{.State.Status}}' "$NAME" 2>/dev/null || echo "없음")
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo "-")
    case "$STATUS" in
      running)
        if [ "$HEALTH" = "unhealthy" ]; then
          warn "[${PHASE}] ${DESC} (${NAME}): running (health: unhealthy)"
          info "  → docker logs ${NAME} --tail 20 으로 원인 확인"
        else
          ok  "[${PHASE}] ${DESC} (${NAME}): running (health: ${HEALTH})"
        fi
        ;;
      exited)   warn "[${PHASE}] ${DESC} (${NAME}): exited" ;;
      없음)      info "[${PHASE}] ${DESC} (${NAME}): 미설치 (선택)" ;;
      *)        warn "[${PHASE}] ${DESC} (${NAME}): ${STATUS}" ;;
    esac
  done

  echo ""
  info "포트 바인딩 현황:"
  docker ps --format "table {{.Names}}\t{{.Ports}}" 2>/dev/null | while read -r LINE; do
    echo -e "  ${C}${LINE}${N}"
  done
fi

# ════════════════════════════════
# 5. API 응답 테스트
# ════════════════════════════════
section "5. API 헬스 엔드포인트 확인"

# ── Phase 2: OpenWebUI (:3000) ──
OWUI_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost:3000/ 2>/dev/null || echo "000")
case "$OWUI_HTTP" in
  200|301|302) ok  "[Phase2] OpenWebUI (:3000): HTTP ${OWUI_HTTP}" ;;
  000)         info "[Phase2] OpenWebUI: 응답 없음 (미실행)" ;;
  *)           warn "[Phase2] OpenWebUI: HTTP ${OWUI_HTTP}" ;;
esac

# ── Phase 2: tools-api (:8000) ──
TOOLS_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost:8000/health 2>/dev/null || echo "000")
case "$TOOLS_HTTP" in
  200) ok  "[Phase2] tools-api (:8000): HTTP 200" ;;
  000) info "[Phase2] tools-api: 응답 없음 (미실행)" ;;
  *)   warn "[Phase2] tools-api: HTTP ${TOOLS_HTTP}" ;;
esac

# ── Phase 2: twilio-bot (:5000) ──
TWILIO_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost:5000/health 2>/dev/null || echo "000")
case "$TWILIO_HTTP" in
  200) ok  "[Phase2] twilio-bot (:5000): HTTP 200" ;;
  000) info "[Phase2] twilio-bot: 응답 없음 (미실행)" ;;
  *)   warn "[Phase2] twilio-bot: HTTP ${TWILIO_HTTP}" ;;
esac

# ── Phase 2: Qdrant (:6333) ──
QDRANT_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost:6333/collections 2>/dev/null || echo "000")
case "$QDRANT_HTTP" in
  200) ok  "[Phase2] Qdrant (:6333): HTTP 200" ;;
  000) info "[Phase2] Qdrant: 응답 없음 (미실행)" ;;
  *)   warn "[Phase2] Qdrant: HTTP ${QDRANT_HTTP}" ;;
esac

# ── Phase 3: Telegram 브릿지 (:8443 외부 / :8444 내부 health) ──
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "telegram-openwebui-bridge"; then
  # 컨테이너 내부에 curl이 없을 수 있으므로 python3 사용
  TG_HEALTH=$(docker exec telegram-openwebui-bridge python3 -c "
import urllib.request
try:
    r = urllib.request.urlopen('http://127.0.0.1:8444/health', timeout=5)
    print(r.read().decode())
except: print('')
" 2>/dev/null || echo "")
  if echo "$TG_HEALTH" | grep -q '"status"'; then
    ok "[Phase3] Telegram 브릿지 /health: OK"
  else
    # health 포트 응답 실패 시 docker inspect로 대체
    TG_RUN=$(docker inspect --format='{{.State.Running}}' telegram-openwebui-bridge 2>/dev/null || echo "false")
    TG_H=$(docker inspect --format='{{.State.Health.Status}}' telegram-openwebui-bridge 2>/dev/null || echo "?")
    if [ "$TG_RUN" = "true" ] && [ "$TG_H" = "unhealthy" ]; then
      warn "[Phase3] Telegram 브릿지: running (health: unhealthy)"
      info "  → docker logs telegram-openwebui-bridge --tail 20 으로 원인 확인"
    elif [ "$TG_RUN" = "true" ]; then
      ok "[Phase3] Telegram 브릿지: running (health: ${TG_H})"
    else
      warn "[Phase3] Telegram 브릿지: health 응답 없음"
    fi
  fi
else
  info "[Phase3] Telegram 브릿지: 미실행"
fi

# ── Browser Agent (:8001 내부) ──
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "browser-agent"; then
  BA_HEALTH=$(docker exec browser-agent python3 -c "
import urllib.request, json
try:
    r = urllib.request.urlopen('http://localhost:8001/health', timeout=5)
    print(r.read().decode())
except: print('')
" 2>/dev/null)
  if echo "$BA_HEALTH" | grep -q '"status"'; then
    BA_VER=$(echo "$BA_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")
    BA_PROV=$(echo "$BA_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('provider','?'))" 2>/dev/null || echo "?")
    BA_MEM=$(echo "$BA_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('memory',False))" 2>/dev/null || echo "?")
    BA_FILES=$(echo "$BA_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('user_files',False))" 2>/dev/null || echo "?")
    ok "[Browser] browser-agent /health: OK (v${BA_VER}, provider: ${BA_PROV})"
    [ "$BA_MEM" = "True" ] && ok "[Browser] 메모리 시스템: 활성" || info "[Browser] 메모리 시스템: 비활성"
    [ "$BA_FILES" = "True" ] && ok "[Browser] 파일 접근: 활성 (~/ai-share)" || info "[Browser] 파일 접근: 비활성"
  else
    # python3 urllib도 실패 시 docker inspect health로 대체
    BA_H=$(docker inspect --format='{{.State.Health.Status}}' browser-agent 2>/dev/null || echo "?")
    if [ "$BA_H" = "healthy" ]; then
      ok "[Browser] browser-agent: healthy (Docker healthcheck 기준)"
    else
      warn "[Browser] browser-agent /health: 내부 응답 없음 (health: ${BA_H})"
    fi
  fi
else
  info "[Browser] browser-agent: 미실행"
fi

# ════════════════════════════════
# 6. Docker 네트워크
# ════════════════════════════════
section "6. Docker 네트워크 확인"

if command -v docker &>/dev/null; then
  # openwebui_default 확인 (모든 Phase 2 서비스 + browser-agent 통신용)
  if docker network inspect openwebui_default &>/dev/null; then
    NET_DEFAULT=$(docker network inspect openwebui_default --format \
      '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
    ok "openwebui_default: ${NET_DEFAULT:-컨테이너 없음}"
    if echo "$NET_DEFAULT" | grep -q "browser-agent"; then
      ok "browser-agent → openwebui_default 연결됨 (open-webui 통신 가능)"
    else
      info "browser-agent가 openwebui_default에 없음 (Browser Agent 미설치 시 정상)"
    fi
  else
    info "openwebui_default 네트워크 없음 (Phase 2 미설치 시 정상)"
  fi

  # openwebui_net 확인 (있으면 좋지만 필수 아님)
  if docker network inspect openwebui_net &>/dev/null; then
    NET_OW=$(docker network inspect openwebui_net --format \
      '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
    ok "openwebui_net: ${NET_OW:-컨테이너 없음}"
  else
    info "openwebui_net 없음 (openwebui_default로 통신 — 정상)"
  fi
fi

# ════════════════════════════════
# 7. 보안 점검
# ════════════════════════════════
section "7. 보안 점검"

# ── Browser Agent API 포트 확인 ──
if docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -q "browser-agent"; then
  BA_BIND=$(docker port browser-agent 8001 2>/dev/null | head -1)
  if echo "$BA_BIND" | grep -q "0.0.0.0"; then
    warn "Browser Agent 포트가 외부에 노출됨 (${BA_BIND}) — 보안 위험!"
    info "  → docker-compose.yml에서 '8001:8001' → '127.0.0.1:8001:8001'으로 변경"
  elif echo "$BA_BIND" | grep -q "127.0.0.1"; then
    ok "Browser Agent 포트 로컬 전용 (${BA_BIND})"
  else
    info "Browser Agent 포트 바인딩: ${BA_BIND:-확인 불가}"
  fi
fi

# ── UFW 방화벽 확인 ──
UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1 || echo "")
if echo "$UFW_STATUS" | grep -qi "Status: active$"; then
  ok "UFW 방화벽 활성화됨"
  sudo ufw status numbered 2>/dev/null | head -15 | while read -r LINE; do
    [ -n "$LINE" ] && info "  $LINE"
  done
else
  warn "UFW 방화벽 비활성화 — 클라우드 서버에서는 활성화 권장"
  info "  → sudo ufw allow ssh && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw enable"
fi

# ── docker-compose.yml 포트 바인딩 점검 ──
info "docker-compose 포트 바인딩 점검:"
if [ -f "${OWUI_DIR}/docker-compose.yml" ]; then
  EXPOSED=$(grep -E '^\s*-\s*"[0-9]+:[0-9]+"' "${OWUI_DIR}/docker-compose.yml" | grep -v "127.0.0.1" | wc -l)
  if [ "$EXPOSED" -eq 0 ]; then
    ok "[Phase2] 모든 포트가 127.0.0.1로 바인딩됨 (외부 접근 차단)"
  else
    grep -E '^\s*-\s*"[0-9]+:[0-9]+"' "${OWUI_DIR}/docker-compose.yml" | grep -v "127.0.0.1" | while read -r LINE; do
      warn "  [Phase2] 외부 노출: ${LINE}"
    done
  fi
fi

# ── Nginx 설정 확인 ──
if [ -f "/etc/nginx/sites-available/twilio-bot" ]; then
  ok "Nginx twilio-bot 설정 파일 존재"
  if grep -q "rate_limit\|limit_req" /etc/nginx/sites-available/twilio-bot 2>/dev/null; then
    ok "Nginx Rate Limiting 설정 확인됨"
  else
    warn "Nginx Rate Limiting 설정 없음"
  fi
  if grep -q "json_audit" /etc/nginx/sites-available/twilio-bot 2>/dev/null; then
    ok "Nginx JSON 감사 로그 설정 확인됨"
  else
    info "Nginx 감사 로그 미설정 (감사 로그 포맷이 conf.d에 있을 수 있음)"
  fi
else
  info "Nginx twilio-bot 설정 없음 (Phase 2 미설치 시 정상)"
fi

# ── 감사 로그 파일 확인 ──
if [ -f "/var/log/nginx/audit.json.log" ]; then
  AUDIT_SIZE=$(du -sh /var/log/nginx/audit.json.log 2>/dev/null | cut -f1)
  ok "JSON 감사 로그 존재 (${AUDIT_SIZE})"
else
  info "JSON 감사 로그 파일 없음 (Nginx 미설치 시 정상)"
fi

# ── 로그 로테이션 확인 ──
if [ -f "/etc/logrotate.d/nginx-audit" ]; then
  ok "Nginx 감사 로그 로테이션 설정됨 (일별, 30일 보관)"
else
  info "감사 로그 로테이션 미설정"
fi

# ════════════════════════════════
# 8. Chromium & Playwright 확인
# ════════════════════════════════
section "8. Browser Use + Chromium 확인"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "browser-agent"; then
  # Browser Use 라이브러리 확인
  BU_VER=$(docker exec browser-agent python3 -c "import browser_use; print('OK')" 2>/dev/null || echo "")
  if [ -n "$BU_VER" ]; then
    ok "Browser Use 설치됨: v${BU_VER}"
  else
    fail "Browser Use 미설치 — 브라우저 에이전트 작동 불가"
  fi

  # Chromium 확인
  CHROME_PATH=$(docker exec browser-agent find /home/appuser/.cache/ms-playwright -name "chrome" -type f 2>/dev/null | head -1)
  if [ -n "$CHROME_PATH" ]; then
    ok "Chromium 설치됨: ${CHROME_PATH}"
  else
    fail "Chromium 미설치"
    info "  → docker exec browser-agent playwright install chromium"
  fi

  # 멀티프로바이더 패키지 확인
  for PKG in "langchain_groq" "langchain_openai" "langchain_anthropic" "langchain_google_genai"; do
    PKG_OK=$(docker exec browser-agent python3 -c "import ${PKG}; print('ok')" 2>/dev/null || echo "")
    if [ "$PKG_OK" = "ok" ]; then
      ok "패키지 ${PKG} 설치됨"
    else
      warn "패키지 ${PKG} 미설치"
    fi
  done

  # 메모리 엔드포인트 확인
  MEM_CHECK=$(docker exec browser-agent python3 -c "
import urllib.request
try:
    r = urllib.request.urlopen('http://localhost:8001/memory', timeout=3)
    print(r.read().decode()[:50])
except: print('')
" 2>/dev/null)
  if [ -n "$MEM_CHECK" ]; then
    ok "메모리 엔드포인트 /memory: 응답 OK"
  else
    info "메모리 엔드포인트: 응답 없음"
  fi

  # 파일 엔드포인트 확인
  FILES_CHECK=$(docker exec browser-agent python3 -c "
import urllib.request
try:
    r = urllib.request.urlopen('http://localhost:8001/files', timeout=3)
    print(r.read().decode()[:50])
except: print('')
" 2>/dev/null)
  if [ -n "$FILES_CHECK" ]; then
    ok "파일 엔드포인트 /files: 응답 OK"
  else
    info "파일 엔드포인트: 응답 없음"
  fi
else
  info "browser-agent 미실행 — Browser Use 확인 건너뜀"
fi

# ════════════════════════════════
# 9. seccomp 프로파일 유효성
# ════════════════════════════════
section "9. seccomp 프로파일 확인"

SECCOMP_FILE="${OWUI_DIR}/browser-agent/seccomp-browser.json"
if [ -f "$SECCOMP_FILE" ]; then
  if python3 -c "import json; json.load(open('${SECCOMP_FILE}'))" 2>/dev/null; then
    SYSCALL_COUNT=$(python3 -c "
import json
d = json.load(open('${SECCOMP_FILE}'))
total = sum(len(r.get('names',[])) for r in d.get('syscalls',[]))
print(total)" 2>/dev/null || echo "?")
    ok "seccomp JSON 유효 (허용 syscall: ${SYSCALL_COUNT}개)"
  else
    fail "seccomp JSON 파싱 오류"
  fi
else
  info "seccomp 파일 없음 (Browser Agent 미설치 시 정상)"
fi

# ════════════════════════════════
# 10. Phase 3 Telegram 설정
# ════════════════════════════════
section "10. Phase 3 Telegram 설정 확인"

if [ -f "${TELEGRAM_DIR}/.env" ]; then
  TG_TOKEN=$(grep "^TELEGRAM_BOT_TOKEN" "${TELEGRAM_DIR}/.env" | head -1 | cut -d= -f2)
  if [ "$TG_TOKEN" = "your_telegram_bot_token_here" ] || [ -z "$TG_TOKEN" ]; then
    warn "Telegram BOT TOKEN 미설정"
  else
    ok "Telegram BOT TOKEN 설정됨"
  fi

  TG_USERS=$(grep "^ALLOWED_USER_IDS" "${TELEGRAM_DIR}/.env" | head -1 | cut -d= -f2)
  if [ -n "$TG_USERS" ]; then
    ok "관리자 User ID 설정됨: ${TG_USERS}"
  else
    warn "관리자 User ID 미설정 — 보안 위험"
  fi

  TG_STATUS=$(docker inspect --format='{{.State.Status}}' telegram-openwebui-bridge 2>/dev/null || echo "없음")
  TG_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' telegram-openwebui-bridge 2>/dev/null || echo "-")
  if [ "$TG_STATUS" = "running" ] && [ "$TG_HEALTH" = "unhealthy" ]; then
    warn "Telegram 브릿지: running (health: unhealthy)"
    info "  → docker logs telegram-openwebui-bridge --tail 20 으로 원인 확인"
  elif [ "$TG_STATUS" = "running" ]; then
    ok "Telegram 브릿지: running (health: ${TG_HEALTH})"
  else
    info "Telegram 브릿지: ${TG_STATUS}"
  fi
else
  info "Phase 3 미설치 (.env 없음)"
fi

# ════════════════════════════════
# 11. Phase 2 Twilio 연동 확인
# ════════════════════════════════
section "11. Phase 2 Twilio + Telegram 연동 확인"

if [ -f "${OWUI_DIR}/.env" ]; then
  # Twilio 설정 확인
  TW_SID=$(grep "^TWILIO_ACCOUNT_SID" "${OWUI_DIR}/.env" 2>/dev/null | head -1 | cut -d= -f2)
  if [ -n "$TW_SID" ]; then
    ok "Twilio Account SID 설정됨"
  else
    info "Twilio 미설정 (선택 기능)"
  fi

  # Telegram 연동 확인 (Phase 3 설치 후 자동 추가)
  TG_TOKEN_OWUI=$(grep "^TELEGRAM_BOT_TOKEN" "${OWUI_DIR}/.env" 2>/dev/null | head -1 | cut -d= -f2)
  TG_CHAT_OWUI=$(grep "^TELEGRAM_CHAT_ID" "${OWUI_DIR}/.env" 2>/dev/null | head -1 | cut -d= -f2)
  if [ -n "$TG_TOKEN_OWUI" ] && [ -n "$TG_CHAT_OWUI" ]; then
    ok "Telegram 알림 연동됨 (CHAT_ID: ${TG_CHAT_OWUI})"
  else
    info "Telegram 알림 미연동 (Phase 3 설치 후 자동 활성화)"
  fi
fi

# ════════════════════════════════
# 12. OpenWebUI Tool 등록 확인
# ════════════════════════════════
section "12. OpenWebUI Tool 등록 확인"

if [ -f "${OWUI_DIR}/.env" ]; then
  OWUI_KEY=$(grep "^OPENWEBUI_API_KEY" "${OWUI_DIR}/.env" 2>/dev/null | head -1 | cut -d= -f2-)
  if [ -n "$OWUI_KEY" ] && [ ${#OWUI_KEY} -ge 20 ]; then
    # Browser Agent Tool 확인
    TOOL_CHECK=$(curl -s -H "Authorization: Bearer ${OWUI_KEY}" \
      http://localhost:3000/api/v1/tools/id/ai_browser_agent 2>/dev/null)
    if echo "$TOOL_CHECK" | grep -q '"id":"ai_browser_agent"'; then
      ok "AI 브라우저 에이전트 Tool 등록됨"
      if echo "$TOOL_CHECK" | grep -q "PLACEHOLDER"; then
        warn "  Tool에 API 키 플레이스홀더 잔존 — Valves에서 수정 필요"
      else
        ok "  Tool API 키 정상 설정됨"
      fi
    else
      info "AI 브라우저 에이전트 Tool 미등록 (Browser Agent 미설치 시 정상)"
    fi

    # Phase 2 Tool 확인 (7개)
    for TOOL_ID in \
      "phone_assistant_v2|전화 어시스턴트" \
      "rag_document_search|RAG 문서 검색" \
      "sms_sender|SMS 보내기" \
      "schedule_manager|예약 스케줄러" \
      "recording_manager|통화 녹음 관리" \
      "pdf_report_manager|PDF 보고서 관리" \
      "feature_status|기능 상태 확인"; do
      IFS='|' read -r TID TNAME <<< "$TOOL_ID"
      TC=$(curl -s -H "Authorization: Bearer ${OWUI_KEY}" \
        "http://localhost:3000/api/v1/tools/id/${TID}" 2>/dev/null)
      if echo "$TC" | grep -q "\"id\":\"${TID}\""; then
        ok "[Phase2] ${TNAME} Tool 등록됨"
      else
        info "[Phase2] ${TNAME} Tool 미등록 (Phase 2 미설치 또는 수동 등록 필요)"
      fi
    done
  else
    info "OPENWEBUI_API_KEY 없음 — Tool 확인 건너뜀"
  fi
fi

# ════════════════════════════════
# 13. Cloudflare Tunnel 확인
# ════════════════════════════════
section "13. Cloudflare Tunnel 확인 (선택)"

if command -v cloudflared &>/dev/null; then
  CF_VER=$(cloudflared --version 2>/dev/null | head -1)
  ok "cloudflared 설치됨: ${CF_VER}"
  CF_STATUS=$(sudo systemctl is-active cloudflared 2>/dev/null || echo "inactive")
  if [ "$CF_STATUS" = "active" ]; then
    ok "Cloudflare Tunnel 서비스 running"
  else
    info "Cloudflare Tunnel 서비스: ${CF_STATUS}"
  fi
else
  info "cloudflared 미설치 (선택 기능 — Cloudflare Tunnel 미사용 시 정상)"
fi

# CF Tunnel Token 저장 확인
if [ -f "${OWUI_DIR}/secrets/cf_tunnel_token" ]; then
  ok "Cloudflare Tunnel Token 저장됨"
fi

# ════════════════════════════════
# 최종 결과
# ════════════════════════════════
echo ""
echo -e "${B}══════════════════════════════════════${N}"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${G}${B}  🎉 모든 항목 검증 통과!${N}"
else
  echo -e "${R}${B}  ❌ ${FAIL_COUNT}개 항목 실패 — 위 내용을 확인하세요.${N}"
fi
echo -e "${B}══════════════════════════════════════${N}"
echo ""
info "유용한 명령어:"
info "  전체 시작:      cd ~/OpenWebUI && docker compose up -d"
info "  전체 상태:      cd ~/OpenWebUI && docker compose ps"
info "  감사 로그:      cd ~/OpenWebUI && ./view-audit-log.sh"
info "  감사 로그 실시간: cd ~/OpenWebUI && ./view-audit-log.sh tail"
info "  Twilio 로그:    docker logs -f twilio-bot"
info "  Telegram 시작:  cd ~/telegram-openwebui-bridge && docker compose up -d"
info "  Telegram 로그:  docker logs -f telegram-openwebui-bridge"
info "  Browser 로그:   docker logs -f browser-agent"
info "  메모리 확인:    curl -s http://localhost:8001/memory | python3 -m json.tool"
info "  파일 목록:      curl -s http://localhost:8001/files | python3 -m json.tool"
info "  재설치:         rm -rf ~/OpenWebUI/browser-agent && bash setup-browser-agent-browser-use-v6.sh"

exit $FAIL_COUNT
