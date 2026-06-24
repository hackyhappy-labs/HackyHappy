#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  설치 검증 스크립트 — verify-install.sh  v6.0.0                     ║
# ║  설치 스크립트 전체 대조 검증 (실제 소스코드 기준 정합성 수정)      ║
# ║                                                                      ║
# ║  검증 대상:                                                          ║
# ║  - Phase 2: start-openwebui-hardened-admin-only.sh (개인용)         ║
# ║             또는 start-openwebui-customer-support.sh (고객상담용)   ║
# ║  - Phase 3: setup-telegram-bridge-calendar.sh                      ║
# ║  - Browser: setup-browser-agent-calendar.sh                       ║
# ║                                                                      ║
# ║  v6.0.0 변경사항:                                                   ║
# ║  - [갱신] 스크립트 파일명 최신화 (admin-only/customer-support 등)   ║
# ║  - [추가] 캘린더 연동 검증 (owui-data 마운트·shared-key·도구 등록)  ║
# ║  - [추가] 보안 강화 검증 (requests/urllib3 CVE 패치 버전)           ║
# ║  - [변경] PIN 인증 검증 → 관리자 번호(ADMIN_NUMBERS) 검증으로 대체  ║
# ║  - [참고] PIN 인증은 폐지됨 (등록된 관리자 번호 기반으로 전환)       ║
# ║  - [버그] 섹션 8 /memory·/files 무인증 호출 → 401 오탐 수정:        ║
# ║          base agent_server.py 의 두 라우트는 verify_api_key 의존성  ║
# ║          을 가져 API 키 설정 시 401 → '응답 없음' 오탐. Bearer 헤더 ║
# ║          를 추가하고 401/403 도 '등록됨'으로 인정하도록 교정        ║
# ║  - [교정] /health/multi 실제 응답키 multi_agent_enabled 로 정합화   ║
# ║          (base 응답: {\"multi_agent_enabled\": true/false})           ║
# ║          섹션 13 grep 패턴을 명시적 키로 교정 (부분일치 의존 제거)  ║
# ║  - [확인] /health 응답키 status·model·version·engine·multi_agent·   ║
# ║          memory·user_files — v7 base 소스와 일치 (유지)             ║
# ║  - [확인] 추가 엔드포인트(/screenshot /history /tasks /sessions     ║
# ║          /pool/status /proxy/status /monitors /browse/stream        ║
# ║          /browse/batch /upload/pdf)는 UPGRADE_PATCH 주입 — 유지      ║
# ║                                                                      ║
# ║  v5.2.0 변경사항 (v5.1.0 대비) — 보안 감사 연동 + 버그 수정:        ║
# ║  - [버그] _ba_get() 내부 Python 최상위 'return' 제거                ║
# ║          (SyntaxError로 섹션 13 엔드포인트 검증이 전부 무력화돼 있었음)║
# ║  - [버그] 641행 [ "$HTTPX_OK"= "ok" ] 공백 누락 → httpx 오탐 수정    ║
# ║  - [개선] fail() 카운터를 (()) → $(()) 로 견고화                     ║
# ║  - [추가] 섹션 15 '보안 강화 검증' 신설 (감사 리포트 항목 실측):    ║
# ║          ① 777 world-writable 디렉토리 탐지                         ║
# ║          ② twilio-bot API_SECRET fail-open 점검                     ║
# ║          ③ 컨테이너 no-new-privileges/cap_drop 일관성               ║
# ║          ④ privileged 모드 보안경고  ⑤ TG 비-상수시간/URL토큰       ║
# ║          ⑥ Browser HMAC 본문 포함 여부                              ║
# ║  - [교정] Phase3 주석 파일명 -hardened → -FINAL.sh                   ║
# ║  - [추가] Phase3 secrets/browser_agent_api_key 선택 검증            ║
# ║  - [주의] 진단 스크립트 특성상 set -e/-u 는 의도적으로 미적용        ║
# ║          (일부 검사 실패 시에도 끝까지 실행되어 합산해야 하므로)     ║
# ║                                                                      ║
# ║  v5.1.0 변경사항 (v5.0.0 대비) — 소스코드 대조 결과 반영:          ║
# ║  - [수정] Telegram telegram_bot.py 경로 /app/bot → /app 으로 교정  ║
# ║          (Dockerfile: COPY telegram_bot.py . → WORKDIR /app)        ║
# ║  - [수정] Telegram Replay 방어 grep 키워드 is_replay 로 교정        ║
# ║  - [추가] Telegram seccomp-bot.json 파일 검증 추가                  ║
# ║  - [수정] Browser /health 응답 필드 provider→engine/model 로 교정  ║
# ║          (실제 응답: status·model·version·engine·multi_agent 등)    ║
# ║  - [추가] Browser 누락 엔드포인트 검증: /screenshot /browse/stream  ║
# ║          /browse/batch /upload/pdf /health/multi /browse/multi      ║
# ║  - [수정] Browser /metrics 는 실재 (UPGRADE_PATCH) — 유지           ║
# ║  - [추가] Browser langgraph 패키지 검증 (Multi-Agent 핵심 의존성)   ║
# ║  - [추가] Browser multi_agent 모듈 파일 8종 검증                    ║
# ║  - [수정] Browser 기능 종합 섹션 번호 14 정리 (중복 13 → 13/14)     ║
# ║                                                                      ║
# ║  v5.0.0 변경사항 (v4.0.0 대비):                                    ║
# ║  - Browser Agent 신규 엔드포인트/Tool/보안 7항목/패키지 검증 추가   ║
# ║  - Telegram 스트리밍/예약/대시보드/보안 26항목 확인                 ║
# ║  - WSL2 환경 감지 + privileged 모드 확인                            ║
# ╚══════════════════════════════════════════════════════════════════════╝
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'
B='\033[1m'; N='\033[0m'
ok()   { echo -e "${G}  ✅  $*${N}"; }
warn() { echo -e "${Y}  ⚠️   $*${N}"; }
fail() { echo -e "${R}  ❌  $*${N}"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo -e "${C}  ℹ️   $*${N}"; }
section() { echo -e "\n${B}── $* ──${N}"; }

FAIL_COUNT=0
OWUI_DIR="${HOME}/OpenWebUI"
TELEGRAM_DIR="${HOME}/telegram-openwebui-bridge"

echo -e "${B}"
cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════════╗
║  OpenWebUI AI 에이전트 — 전체 설치 검증 v5.3.0                      ║
║  Phase 2 + Phase 3 + Browser Agent v7 완전 대조 (섹션 15개)         ║
║  ※ secrets/data 확인에 sudo 사용 (uid 1001 소유 대응)              ║
╚══════════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${N}"

# ════════════════════════════════
# 1. 디렉토리 구조
# ════════════════════════════════
section "1. 디렉토리 구조 확인 (25개)"

declare -a DIR_LIST=(
  # ── Phase 2: start-openwebui-hardened-admin-only.sh / customer-support.sh ──
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
  # ── Phase 3: setup-telegram-bridge-calendar.sh ──
  "Phase3|telegram-bridge 루트|${TELEGRAM_DIR}"
  "Phase3|telegram-bridge/bot|${TELEGRAM_DIR}/bot"
  "Phase3|telegram-bridge/data|${TELEGRAM_DIR}/data"
  "Phase3|telegram-bridge/logs|${TELEGRAM_DIR}/logs"
  "Phase3|telegram-bridge/secrets|${TELEGRAM_DIR}/secrets"
  # ── Browser Agent: setup-browser-agent-calendar.sh ──
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
section "2. 필수 파일 확인 (39개)"

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
  # admin_pin: PIN 인증은 폐지됐으나 호환용으로 자동 생성·저장됨 (통화 인증엔 미사용)
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
  "Phase3|bot/seccomp-bot.json|${TELEGRAM_DIR}/bot/seccomp-bot.json"
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
  "Phase2|twilio-bot/data/schedules.json|${OWUI_DIR}/twilio-bot/data/schedules.json" \
  "Phase3|secrets/browser_agent_api_key (Browser 연동 시)|${TELEGRAM_DIR}/secrets/browser_agent_api_key"; do
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
    BA_MODEL=$(echo "$BA_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('model','?'))" 2>/dev/null || echo "?")
    BA_ENGINE=$(echo "$BA_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('engine','?'))" 2>/dev/null || echo "?")
    BA_MULTI=$(echo "$BA_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('multi_agent',False))" 2>/dev/null || echo "?")
    BA_MEM=$(echo "$BA_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('memory',False))" 2>/dev/null || echo "?")
    BA_FILES=$(echo "$BA_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('user_files',False))" 2>/dev/null || echo "?")
    ok "[Browser] browser-agent /health: OK (v${BA_VER}, engine: ${BA_ENGINE}, model: ${BA_MODEL})"
    [ "$BA_MULTI" = "True" ] && ok "[Browser] Multi-Agent(LangGraph): 활성" || warn "[Browser] Multi-Agent: 비활성 — multi_agent.graph import 실패 가능"
    [ "$BA_MEM" = "True" ] && ok "[Browser] 메모리 시스템: 활성" || info "[Browser] 메모리 시스템: 비활성"
    [ "$BA_FILES" = "True" ] && ok "[Browser] 파일 접근: 활성 (~/ai-share)" || info "[Browser] 파일 접근: 비활성"

    # ── 신규 엔드포인트 9개 검증 ─────────────────────────────────
    info "[Browser] 신규 엔드포인트 확인:"
    BA_API_KEY=$(grep "^BROWSER_AGENT_API_KEY=" "${OWUI_DIR}/.env" 2>/dev/null | cut -d= -f2- || echo "")
    _ba_check() {
      local path="$1" desc="$2" method="${3:-GET}"
      local result
      result=$(docker exec browser-agent python3 -c "
import urllib.request
req = urllib.request.Request('http://localhost:8001${path}',
  headers={'Authorization':'Bearer ${BA_API_KEY}'},
  method='${method}')
try:
    r = urllib.request.urlopen(req, timeout=3)
    print(r.status)
except urllib.error.HTTPError as e: print(e.code)
except: print('ERR')
" 2>/dev/null || echo "ERR")
      case "$result" in
        200|201) ok "  /$(echo ${path}|sed 's|/||'): 응답 OK (${desc})" ;;
        405)     ok "  ${path}: 등록됨 (${desc}, POST 전용)" ;;
        404)     warn "  ${path}: 404 — 패치 미적용 가능성" ;;
        401|403) warn "  ${path}: 인증 오류 — API Key 확인 필요" ;;
        ERR|"")  warn "  ${path}: 응답 없음 (${desc})" ;;
        *)       info "  ${path}: HTTP ${result} (${desc})" ;;
      esac
    }
    # ── GET 엔드포인트 (UPGRADE_PATCH + base) ──
    _ba_check "/history"       "작업 히스토리"
    _ba_check "/tasks"         "실행 중 작업 목록"
    _ba_check "/sessions"      "세션 목록"
    _ba_check "/monitors"      "모니터링 목록"
    _ba_check "/pool/status"   "브라우저 풀 상태"
    _ba_check "/proxy/status"  "프록시 설정"
    _ba_check "/metrics"       "서버 메트릭"
    _ba_check "/memory"        "장기 메모리"
    _ba_check "/files"         "파일 목록"
    _ba_check "/health/multi"  "Multi-Agent 헬스"
    # ── POST 엔드포인트 (GET 호출 시 405 → 등록 확인용) ──
    _ba_check "/screenshot"    "스크린샷 캡처"
    _ba_check "/browse/stream" "SSE 스트리밍 브라우징"
    _ba_check "/browse/batch"  "배치 브라우징"
    _ba_check "/browse/multi"  "Multi-Agent 브라우징"
    _ba_check "/upload/pdf"    "PDF 업로드"
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

# ── Browser Agent 보안 7항목 패치 확인 ──
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^browser-agent$"; then
  info "Browser Agent 보안 패치 확인:"
  BA_CODE=$(docker exec browser-agent cat /app/agent_server.py 2>/dev/null || echo "")
  if [ -n "$BA_CODE" ]; then
    echo "$BA_CODE" | grep -q "_ip_blocked\|IP_LOCKOUT"        && ok "  ① IP 차단 블랙리스트 패치됨"     || warn "  ① IP 차단 블랙리스트 미적용"
    echo "$BA_CODE" | grep -q "verify_request_signature"        && ok "  ② 요청 서명 검증 패치됨"         || info "  ② 요청 서명 검증 미적용 (선택)"
    echo "$BA_CODE" | grep -q "filter_response\|RESP_FILTERS"  && ok "  ③ AI 응답 필터링 패치됨"         || warn "  ③ AI 응답 필터링 미적용"
    echo "$BA_CODE" | grep -q "PATH_NULL_BYTE\|realpath"       && ok "  ④ Path Traversal 이중 검증됨"    || warn "  ④ Path Traversal 단일 검증"
    echo "$BA_CODE" | grep -q "validate_memory_update"          && ok "  ⑤ 메모리 스키마 검증 패치됨"     || warn "  ⑤ 메모리 스키마 검증 미적용"
    echo "$BA_CODE" | grep -q "pids.*100\|pids: 100"           && ok "  ⑥ Docker pids 제한 설정됨"       || info "  ⑥ Docker pids 미설정 (compose 설정)"
    echo "$BA_CODE" | grep -q "RotatingFileHandler"             && ok "  ⑦ 감사 로그 RotatingHandler"     || warn "  ⑦ 감사 로그 로테이션 미적용"
  else
    info "  agent_server.py 읽기 실패"
  fi
fi

# ── Telegram 브릿지 보안 26항목 패치 확인 ──
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "telegram-openwebui-bridge"; then
  info "Telegram 브릿지 보안/기능 확인:"
  TG_CODE=$(docker exec telegram-openwebui-bridge cat /app/telegram_bot.py 2>/dev/null || echo "")
  if [ -n "$TG_CODE" ]; then
    echo "$TG_CODE" | grep -q "is_replay\|update_id"        && ok "  ⑤ Replay Attack 방어됨"        || warn "  ⑤ Replay Attack 방어 미적용"
    echo "$TG_CODE" | grep -q "sanitize_input\|jailbreak"    && ok "  ⑥ Prompt Injection 방어됨"     || warn "  ⑥ Prompt Injection 방어 미적용"
    echo "$TG_CODE" | grep -q "verify_file_magic"             && ok "  ⑦ Magic Bytes 검증됨"          || warn "  ⑦ Magic Bytes 검증 미적용"
    echo "$TG_CODE" | grep -q "filter_ai_response"            && ok "  ⑧ AI 응답 필터링됨"            || warn "  ⑧ AI 응답 필터링 미적용"
    echo "$TG_CODE" | grep -q "_DASH_FAIL\|DASH_LOCKOUT"     && ok "  ⑪ 대시보드 Brute-force 방지됨" || warn "  ⑪ 대시보드 Brute-force 미적용"
    echo "$TG_CODE" | grep -q "stream_openwebui_chat"         && ok "  스트리밍 응답 구현됨"           || warn "  스트리밍 응답 미적용"
    echo "$TG_CODE" | grep -q "_scheduler_loop"               && ok "  예약 기능 구현됨"              || warn "  예약 기능 미적용"
    echo "$TG_CODE" | grep -q "get_available_models"          && ok "  /model 명령 함수 존재"          || warn "  /model 명령 함수 누락"
    echo "$TG_CODE" | grep -q "dashboard_server"              && ok "  대시보드 서버 구현됨"           || warn "  대시보드 서버 미구현"
  else
    info "  telegram_bot.py 읽기 실패"
  fi
fi

# ── WSL2 환경 privileged 모드 확인 ──
if grep -qiE "microsoft|WSL" /proc/version 2>/dev/null; then
  info "WSL2 환경 감지됨:"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "telegram-openwebui-bridge"; then
    TG_PRIV=$(docker inspect --format='{{.HostConfig.Privileged}}' telegram-openwebui-bridge 2>/dev/null || echo "false")
    [ "$TG_PRIV" = "true" ] && ok "  Telegram: privileged 모드 (WSL2 openat2 우회)" \
                             || warn "  Telegram: privileged 모드 아님 — openat2 오류 발생 가능"
  fi
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^browser-agent$"; then
    BA_PRIV=$(docker inspect --format='{{.HostConfig.Privileged}}' browser-agent 2>/dev/null || echo "false")
    [ "$BA_PRIV" = "true" ] && ok "  Browser Agent: privileged 모드 (WSL2 호환)" \
                             || info "  Browser Agent: privileged 모드 아님"
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

  # 필수 패키지 확인 (기본 + 신규)
  for PKG in "langchain_groq" "langchain_openai" "langchain_anthropic" "langchain_google_genai"; do
    PKG_OK=$(docker exec browser-agent python3 -c "import ${PKG}; print('ok')" 2>/dev/null || echo "")
    if [ "$PKG_OK" = "ok" ]; then
      ok "패키지 ${PKG} 설치됨"
    else
      warn "패키지 ${PKG} 미설치"
    fi
  done

  # 신규 패키지 확인 (v7 업그레이드)
  info "신규 패키지 확인 (v7 업그레이드):"
  SSE_OK=$(docker exec browser-agent python3 -c "import sse_starlette; print('ok')" 2>/dev/null || echo "")
  XLSX_OK=$(docker exec browser-agent python3 -c "import openpyxl; print('ok')" 2>/dev/null || echo "")
  HTTPX_OK=$(docker exec browser-agent python3 -c "import httpx; print('ok')" 2>/dev/null || echo "")
  LG_OK=$(docker exec browser-agent python3 -c "import langgraph; print('ok')" 2>/dev/null || echo "")
  [ "$SSE_OK"  = "ok" ] && ok "  sse-starlette 설치됨 (SSE 스트리밍)" || warn "  sse-starlette 미설치 — /browse/stream 비활성"
  [ "$XLSX_OK" = "ok" ] && ok "  openpyxl 설치됨 (Excel 내보내기)"   || warn "  openpyxl 미설치 — Excel 저장 불가"
  [ "$HTTPX_OK" = "ok" ] && ok "  httpx 설치됨"                        || info "  httpx 미설치 (선택)"
  [ "$LG_OK"   = "ok" ] && ok "  langgraph 설치됨 (Multi-Agent 핵심)" || warn "  langgraph 미설치 — Multi-Agent(/browse/multi) 비활성"

  # multi_agent 모듈 파일 8종 확인 (컨테이너 내부)
  info "Multi-Agent 모듈 확인 (/app/multi_agent):"
  for MAFILE in __init__.py state.py groq_utils.py supervisor.py \
                research_agent.py browser_tool_agent.py summarizer.py graph.py; do
    if docker exec browser-agent test -f "/app/multi_agent/${MAFILE}" 2>/dev/null; then
      ok "  multi_agent/${MAFILE}"
    else
      warn "  multi_agent/${MAFILE} 없음 — Multi-Agent 불완전"
    fi
  done
  # graph.build_graph import 가능 여부
  GRAPH_OK=$(docker exec browser-agent python3 -c "from multi_agent.graph import build_graph; print('ok')" 2>/dev/null || echo "")
  [ "$GRAPH_OK" = "ok" ] && ok "  multi_agent.graph.build_graph import 성공" || warn "  build_graph import 실패 — /health multi_agent=false 원인"

  # ── /memory · /files 엔드포인트 확인 ──────────────────────────────
  # 주의: base agent_server.py 의 /memory·/files 는 verify_api_key 의존성을
  #       가짐 → API 키 설정 시 인증 헤더 없으면 401. Bearer 헤더 필수.
  BA_KEY8=$(grep "^BROWSER_AGENT_API_KEY=" "${OWUI_DIR}/.env" 2>/dev/null | cut -d= -f2- || echo "")

  # 메모리 엔드포인트 확인
  MEM_CHECK=$(docker exec browser-agent python3 -c "
import urllib.request
req = urllib.request.Request('http://localhost:8001/memory',
  headers={'Authorization':'Bearer ${BA_KEY8}'})
try:
    r = urllib.request.urlopen(req, timeout=3)
    print('OK:' + r.read().decode()[:50])
except urllib.error.HTTPError as e:
    print('HTTP:' + str(e.code))
except Exception: print('')
" 2>/dev/null)
  case "$MEM_CHECK" in
    OK:*)           ok "메모리 엔드포인트 /memory: 응답 OK" ;;
    HTTP:401|HTTP:403) ok "메모리 엔드포인트 /memory: 등록됨 (인증 필요)" ;;
    HTTP:*)         warn "메모리 엔드포인트 /memory: ${MEM_CHECK#HTTP:}" ;;
    *)              info "메모리 엔드포인트: 응답 없음" ;;
  esac

  # 파일 엔드포인트 확인
  FILES_CHECK=$(docker exec browser-agent python3 -c "
import urllib.request
req = urllib.request.Request('http://localhost:8001/files',
  headers={'Authorization':'Bearer ${BA_KEY8}'})
try:
    r = urllib.request.urlopen(req, timeout=3)
    print('OK:' + r.read().decode()[:50])
except urllib.error.HTTPError as e:
    print('HTTP:' + str(e.code))
except Exception: print('')
" 2>/dev/null)
  case "$FILES_CHECK" in
    OK:*)           ok "파일 엔드포인트 /files: 응답 OK" ;;
    HTTP:401|HTTP:403) ok "파일 엔드포인트 /files: 등록됨 (인증 필요)" ;;
    HTTP:*)         warn "파일 엔드포인트 /files: ${FILES_CHECK#HTTP:}" ;;
    *)              info "파일 엔드포인트: 응답 없음" ;;
  esac
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

  # 통화 인증: 관리자 번호(ADMIN_NUMBERS) 확인 — PIN 폐지, 번호 기반 인증
  ADM_NUM=$(grep "^ADMIN_NUMBERS=" "${OWUI_DIR}/.env" 2>/dev/null | head -1 | cut -d= -f2-)
  if [ -n "$ADM_NUM" ]; then
    NUM_COUNT=$(echo "$ADM_NUM" | tr ',' '\n' | grep -c .)
    ok "관리자 번호 설정됨 (${NUM_COUNT}개) — 이 번호만 봇에게 통화 가능 (PIN 폐지)"
  else
    warn "ADMIN_NUMBERS 미설정 — 통화 인증 대상 없음. 설치 시 본인 번호 입력 확인 필요"
  fi
  # 운영 모드 감지 (개인용 vs 고객상담용)
  if [ -f "${OWUI_DIR}/twilio-bot/twilio_bot.py" ]; then
    if grep -q "고객 상담 연결" "${OWUI_DIR}/twilio-bot/twilio_bot.py" 2>/dev/null; then
      ok "운영 모드: 고객 상담용 (모르는 번호도 AI 응대, 캘린더 등은 관리자만)"
    else
      ok "운영 모드: 개인용 (등록된 관리자 번호만 통화)"
    fi
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

      # Tool 내 신규 함수 존재 여부 확인
      TOOL_CONTENT=$(echo "$TOOL_CHECK" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('content',''))" 2>/dev/null || echo "")
      if [ -n "$TOOL_CONTENT" ]; then
        info "  Tool 신규 함수 확인:"
        echo "$TOOL_CONTENT" | grep -q "search_wikipedia"  && ok "    search_wikipedia() 존재"   || warn "    search_wikipedia() 없음 — 위키 패치 미적용"
        echo "$TOOL_CONTENT" | grep -q "take_screenshot"   && ok "    take_screenshot() 존재"    || warn "    take_screenshot() 없음 — 업그레이드 미적용"
        echo "$TOOL_CONTENT" | grep -q "search_map"        && ok "    search_map() 존재"         || warn "    search_map() 없음"
        echo "$TOOL_CONTENT" | grep -q "download_file"     && ok "    download_file() 존재"      || warn "    download_file() 없음"
        echo "$TOOL_CONTENT" | grep -q "export_to_excel"   && ok "    export_to_excel() 존재"    || warn "    export_to_excel() 없음"
        echo "$TOOL_CONTENT" | grep -q "monitor_price"     && ok "    monitor_price() 존재"      || warn "    monitor_price() 없음"
        echo "$TOOL_CONTENT" | grep -q "check_monitors"    && ok "    check_monitors() 존재"     || warn "    check_monitors() 없음"
        echo "$TOOL_CONTENT" | grep -q "get_today_schedule" && ok "    get_today_schedule() 존재 (캘린더)" || info "    get_today_schedule() 없음 — 캘린더 패치 미적용"
        echo "$TOOL_CONTENT" | grep -q "browse_stream\|stream"   && ok "    스트리밍 브라우징 함수 존재" || info "    스트리밍 브라우징 함수 없음"
        echo "$TOOL_CONTENT" | grep -q "browse_batch\|multi"     && ok "    배치/멀티 브라우징 함수 존재" || info "    배치/멀티 함수 없음"
      fi
    else
      info "AI 브라우저 에이전트 Tool 미등록 (Browser Agent 미설치 시 정상)"
    fi

    # Phase 2 Tool 확인 (9개)
    for TOOL_ID in \
      "phone_assistant_v2|전화 어시스턴트" \
      "rag_document_search|RAG 문서 검색" \
      "sms_sender|SMS 보내기" \
      "schedule_manager|예약 스케줄러" \
      "recording_manager|통화 녹음 관리" \
      "pdf_report_manager|PDF 보고서 관리" \
      "feature_status|기능 상태 확인" \
      "media_manager|미디어 관리" \
      "calendar_today|캘린더 (오늘 일정)"; do
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
# 12-5. 캘린더 연동 검증 (전화·채팅 키 공유)
# ════════════════════════════════
section "12-5. 캘린더 연동 검증 (재발 방지 포함)"

# (1) twilio-bot 에 owui-data 볼륨 마운트 확인 (재발 방지 핵심)
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^twilio-bot$"; then
  MOUNT_CHECK=$(docker inspect twilio-bot --format '{{range .Mounts}}{{.Destination}} {{end}}' 2>/dev/null)
  if echo "$MOUNT_CHECK" | grep -q "/owui-data"; then
    ok "twilio-bot에 /owui-data 볼륨 마운트됨 (캘린더 키 공유 가능)"
  else
    warn "twilio-bot에 /owui-data 마운트 없음 — 캘린더 compose 미적용"
    info "  복구: cd ~/OpenWebUI && ./calendar-up.sh  (또는 .env COMPOSE_FILE 확인)"
  fi

  # (2) 공유 키 파일 존재 + 권한(644) 확인
  if docker exec twilio-bot test -f /owui-data/shared-key/openwebui_api_key 2>/dev/null; then
    KEY_LEN=$(docker exec twilio-bot sh -c 'wc -c < /owui-data/shared-key/openwebui_api_key' 2>/dev/null | tr -d ' ')
    if [ -n "$KEY_LEN" ] && [ "$KEY_LEN" -gt 20 ]; then
      ok "캘린더 공유 키 저장됨 (${KEY_LEN} bytes) — 전화 캘린더 사용 가능"
    else
      warn "공유 키 파일이 비어있음 — 채팅에서 '오늘 일정' 1회 실행 필요"
    fi
  else
    info "캘린더 공유 키 미저장 — 채팅 도구 밸브에 키 입력 후 '오늘 일정' 1회 실행 필요"
  fi
else
  info "twilio-bot 미실행 — 캘린더 연동 검증 건너뜀"
fi

# (3) 재발 방지: .env COMPOSE_FILE 고정 확인
if [ -f "${OWUI_DIR}/.env" ]; then
  if grep -q "^COMPOSE_FILE=" "${OWUI_DIR}/.env" 2>/dev/null; then
    ok ".env COMPOSE_FILE 고정됨 (재발 방지 적용 — 어떤 방식으로 띄워도 캘린더 유지)"
  else
    info ".env COMPOSE_FILE 미설정 — 메인 compose 마운트로도 동작하나 고정 권장"
  fi
fi

# ════════════════════════════════
# 13. Browser Agent 기능 종합 검증
# ════════════════════════════════
section "13. Browser Agent 기능 종합 검증 (v7)"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^browser-agent$"; then
  BA_API_KEY=$(grep "^BROWSER_AGENT_API_KEY=" "${OWUI_DIR}/.env" 2>/dev/null | cut -d= -f2- || echo "")

  _ba_get() {
    docker exec browser-agent python3 -c "
import urllib.request, json
req = urllib.request.Request('http://localhost:8001$1',
  headers={'Authorization':'Bearer ${BA_API_KEY}'})
try:
    r = urllib.request.urlopen(req, timeout=5)
    print(r.read().decode()[:200])
except urllib.error.HTTPError as e:
    print('{"_http_err":' + str(e.code) + '}')
except Exception as e:
    print('{"_err":"' + str(e)[:50] + '"}')
" 2>/dev/null || echo ""
  }

  # ── 스크린샷 API ──
  info "[BA] 엔드포인트 기능 검증:"
  HIST=$(_ba_get "/history")
  if echo "$HIST" | grep -q '"history"'; then
    HIST_CNT=$(echo "$HIST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo "?")
    ok "  /history: 응답 OK (총 ${HIST_CNT}건)"
  elif echo "$HIST" | grep -q "_http_err"; then
    warn "  /history: 오류 — 패치 미적용 가능성"
  else
    info "  /history: 응답 없음"
  fi

  TASKS=$(_ba_get "/tasks")
  if echo "$TASKS" | grep -q '"active"'; then
    ACT=$(echo "$TASKS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "?")
    ok "  /tasks: 응답 OK (활성 작업 ${ACT}개)"
  else
    warn "  /tasks: 응답 없음 — 패치 미적용 가능성"
  fi

  POOL=$(_ba_get "/pool/status")
  if echo "$POOL" | grep -q '"pool_enabled"'; then
    POOL_EN=$(echo "$POOL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pool_enabled',False))" 2>/dev/null || echo "?")
    if [ "$POOL_EN" = "True" ]; then
      ok "  /pool/status: 브라우저 풀 활성 (BROWSER_POOL_SIZE > 0)"
    else
      ok "  /pool/status: 응답 OK (풀 비활성 — BROWSER_POOL_SIZE=0)"
    fi
  else
    warn "  /pool/status: 응답 없음"
  fi

  PROXY=$(_ba_get "/proxy/status")
  if echo "$PROXY" | grep -q '"proxy_enabled"'; then
    PROXY_EN=$(echo "$PROXY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('proxy_enabled',False))" 2>/dev/null || echo "?")
    if [ "$PROXY_EN" = "True" ]; then
      PROXY_SRV=$(echo "$PROXY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('proxy_server',''))" 2>/dev/null || echo "")
      ok "  /proxy/status: 프록시 활성 (${PROXY_SRV})"
    else
      ok "  /proxy/status: 응답 OK (프록시 미사용)"
    fi
  else
    warn "  /proxy/status: 응답 없음"
  fi

  MONS=$(_ba_get "/monitors")
  if echo "$MONS" | grep -q '"monitors"'; then
    MON_CNT=$(echo "$MONS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "?")
    ok "  /monitors: 응답 OK (등록된 모니터 ${MON_CNT}개)"
  else
    warn "  /monitors: 응답 없음"
  fi

  SESS=$(_ba_get "/sessions")
  if echo "$SESS" | grep -q '"sessions"'; then
    SESS_CNT=$(echo "$SESS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "?")
    ok "  /sessions: 응답 OK (저장된 세션 ${SESS_CNT}개)"
  else
    warn "  /sessions: 응답 없음"
  fi

  # ── Multi-Agent (LangGraph) 동작 확인 ──
  # base 응답: {"multi_agent_enabled": true}  또는  {"multi_agent_enabled": false, "error": "..."}
  MHLT=$(_ba_get "/health/multi")
  if echo "$MHLT" | grep -q '"multi_agent_enabled"[[:space:]]*:[[:space:]]*true'; then
    ok "  /health/multi: 응답 OK (multi_agent_enabled=true — 그래프 로드됨)"
  elif echo "$MHLT" | grep -q '"multi_agent_enabled"[[:space:]]*:[[:space:]]*false'; then
    warn "  /health/multi: multi_agent_enabled=false — multi_agent.graph import 실패 가능"
  elif echo "$MHLT" | grep -q "_http_err"; then
    warn "  /health/multi: 오류 — multi_agent 모듈 import 실패 가능"
  else
    info "  /health/multi: 응답 없음 (Multi-Agent 미활성)"
  fi

  # ── 검색 우선순위 설정 확인 ──
  info "[BA] 검색 우선순위 설정:"
  TOOL_PY=$(docker exec browser-agent cat /app/openwebui_tool.py 2>/dev/null || echo "")
  if [ -n "$TOOL_PY" ]; then
    echo "$TOOL_PY" | grep -q "_is_encyclopedic_query\|encyclopedic"       && ok "  백과사전형 질문 감지 함수 존재"       || warn "  백과사전형 질문 감지 없음"
    echo "$TOOL_PY" | grep -q "ko.wikipedia.org"       && ok "  한국어 위키피디아 검색 설정됨"       || warn "  한국어 위키피디아 없음"
    echo "$TOOL_PY" | grep -q "search_wikipedia"       && ok "  search_wikipedia() Tool 존재"       || warn "  search_wikipedia() 없음"
    TOOL_COUNT=$(echo "$TOOL_PY" | grep -c "async def " || echo "0")
    ok "  Tool 함수 총 ${TOOL_COUNT}개"
  fi

  # ── ai-share 마운트 확인 ──
  SHARE_CHECK=$(docker exec browser-agent ls /app/data/user_files 2>/dev/null && echo "ok" || echo "")
  if [ "$SHARE_CHECK" = "ok" ]; then
    ok "[BA] ~/ai-share 마운트 정상 (/app/data/user_files)"
  else
    warn "[BA] ~/ai-share 마운트 실패 — 파일 공유 불가"
    info "  → docker-compose.yml volumes에 ~/ai-share:/app/data/user_files 확인"
  fi

else
  info "browser-agent 미실행 — 섹션 13 건너뜀"
fi

# ════════════════════════════════
# 14. Cloudflare Tunnel 확인
# ════════════════════════════════
section "14. Cloudflare Tunnel 확인 (선택)"

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
# 15. 보안 강화 검증 (보안 감사 리포트 연동) [v5.2.0 신규]
# ════════════════════════════════
section "15. 보안 강화 검증 (감사 리포트 연동)"

# ── (0) CVE 패치 버전 검증 (requests/urllib3) ──
info "의존성 CVE 패치 버전 점검:"
for REQ in "${OWUI_DIR}/twilio-bot/requirements.txt" "${OWUI_DIR}/tools-api/requirements.txt"; do
  if [ -f "$REQ" ]; then
    RNAME="${REQ##*/twilio-bot/}"; RNAME="${RNAME##*/tools-api/}"
    LABEL=$(echo "$REQ" | grep -o 'twilio-bot\|tools-api')
    # requests >= 2.34.2 (CVE-2024-47081 netrc 자격증명 유출)
    RV=$(grep -iE "^requests>=" "$REQ" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    if [ -n "$RV" ]; then
      # 2.34.2 이상인지 단순 비교
      if printf '%s\n2.34.2\n' "$RV" | sort -V | head -1 | grep -q "2.34.2"; then
        ok "  [${LABEL}] requests ${RV} — CVE-2024-47081 패치됨"
      else
        warn "  [${LABEL}] requests ${RV} — 2.34.2 미만, netrc 유출 CVE 위험. 업그레이드 권장"
      fi
    fi
    # urllib3 >= 2.6.3 (CVE-2026-21441 DoS)
    if grep -iqE "^urllib3>=" "$REQ" 2>/dev/null; then
      ok "  [${LABEL}] urllib3 패치 명시됨 (DoS CVE 대응)"
    else
      info "  [${LABEL}] urllib3 미명시 (requests 의존성으로 설치되나 명시 권장)"
    fi
  fi
done

# ── (0-2) 캘린더 코드 trust_env 보안 점검 ──
if [ -f "${OWUI_DIR}/twilio-bot/twilio_bot.py" ]; then
  if grep -q "trust_env" "${OWUI_DIR}/twilio-bot/twilio_bot.py" 2>/dev/null; then
    ok "캘린더 조회 trust_env=False 적용됨 (환경 자격증명 비활성화)"
  else
    info "캘린더 조회 trust_env 미적용 — netrc 자격증명 비활성화 권장"
  fi
fi

# ── (1) world-writable(777) 디렉토리 탐지 ──
# 설치 스크립트의 'chmod 777 폴백'이 적용됐는지 점검 — 같은 호스트의 다른 로컬 사용자 접근 위험
info "world-writable(기타 사용자 쓰기) 디렉토리 점검:"
WW_FOUND=0
for D in \
  "${OWUI_DIR}/twilio-bot/data" \
  "${OWUI_DIR}/twilio-bot/logs" \
  "${OWUI_DIR}/logs" \
  "${TELEGRAM_DIR}/logs" \
  "${TELEGRAM_DIR}/data"; do
  if [ -d "$D" ] || sudo test -d "$D" 2>/dev/null; then
    P=$(sudo stat -c "%a" "$D" 2>/dev/null || stat -c "%a" "$D" 2>/dev/null || echo "")
    OTHER="${P: -1}"   # 기타(other) 권한 비트
    case "$OTHER" in
      2|3|6|7) warn "  ${D##$HOME/}: ${P} — 기타 사용자 쓰기 가능(777 폴백 흔적). chmod 750/770 권장"; WW_FOUND=1 ;;
      *)       [ -n "$P" ] && ok "  ${D##$HOME/}: ${P}" ;;
    esac
  fi
done
[ "$WW_FOUND" -eq 0 ] && ok "  world-writable 디렉토리 없음"

# ── (2) twilio-bot API_SECRET fail-open 점검 ──
# secrets/api_secret 가 비어 있으면 require_api_secret 가 인증 없이 통과(fail-open) — 무인증 위험
AS_FILE="${OWUI_DIR}/secrets/api_secret"
if [ -f "$AS_FILE" ] || sudo test -f "$AS_FILE" 2>/dev/null; then
  AS_LEN=$(sudo cat "$AS_FILE" 2>/dev/null | tr -d '\n' | wc -c 2>/dev/null || echo 0)
  if [ "${AS_LEN:-0}" -ge 16 ]; then
    ok "twilio-bot API_SECRET 설정됨 (${AS_LEN}자) — fail-open 아님"
  else
    warn "twilio-bot API_SECRET 비어있음/짧음 — API 인증이 사실상 비활성(fail-open) 위험"
    info "  → 감사 리포트 H4: API_SECRET 미설정 시 fail-closed(503)로 변경 권장"
  fi
else
  info "secrets/api_secret 없음 (Phase 2 미설치 시 정상)"
fi

# ── (3) 컨테이너 하드닝 일관성 (no-new-privileges + cap_drop) ──
# 감사 리포트 M4: open-webui/qdrant 에 누락돼 있던 항목
if command -v docker &>/dev/null; then
  info "컨테이너 보안옵션 점검 (no-new-privileges + cap_drop):"
  _hardening_check() {
    local NAME="$1"
    docker inspect "$NAME" &>/dev/null || { info "  ${NAME}: 미실행 (건너뜀)"; return; }
    local SO CD nnp=no cap=no
    SO=$(docker inspect --format '{{.HostConfig.SecurityOpt}}' "$NAME" 2>/dev/null || echo "")
    CD=$(docker inspect --format '{{.HostConfig.CapDrop}}' "$NAME" 2>/dev/null || echo "")
    echo "$SO" | grep -q "no-new-privileges" && nnp=yes
    echo "$CD" | grep -qiE "ALL|all|NET_RAW" && cap=yes
    if [ "$nnp" = yes ] && [ "$cap" = yes ]; then
      ok "  ${NAME}: no-new-privileges ✔ / cap_drop ✔"
    elif [ "$nnp" = yes ] || [ "$cap" = yes ]; then
      warn "  ${NAME}: 일부만 적용 (nnp=${nnp}, cap_drop=${cap})"
    else
      warn "  ${NAME}: 하드닝 미적용 — compose에 no-new-privileges/cap_drop:ALL 추가 권장"
    fi
  }
  for N in openwebui-open-webui-1 openwebui-qdrant-1 openwebui-openapi-tools-1 \
           twilio-bot browser-agent telegram-openwebui-bridge; do
    _hardening_check "$N"
  done
fi

# ── (4) privileged 모드 = 보안 경계 약화 경고 ──
# 감사 리포트 M3: WSL2 privileged 폴백은 cap_drop/seccomp 무력화 + 컨테이너 탈출 위험
if command -v docker &>/dev/null; then
  for N in browser-agent telegram-openwebui-bridge; do
    PRIV=$(docker inspect --format='{{.HostConfig.Privileged}}' "$N" 2>/dev/null || echo "")
    if [ "$PRIV" = "true" ]; then
      warn "[보안] ${N}: privileged 모드 — cap_drop/seccomp 무력화 + 컨테이너 탈출 위험. 신뢰 호스트에서만 사용"
    fi
  done
fi

# ── (5) Telegram 코드: 비-상수시간 비교 / URL 토큰 노출 점검 ──
if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "telegram-openwebui-bridge"; then
  TG_SRC=$(docker exec telegram-openwebui-bridge cat /app/telegram_bot.py 2>/dev/null || echo "")
  if [ -n "$TG_SRC" ]; then
    if echo "$TG_SRC" | grep -qE '!=[[:space:]]*f"Bearer'; then
      warn "[보안] metrics_auth 비-상수시간 비교(!=) 사용 — hmac.compare_digest 로 교체 권장 (감사 M1)"
    else
      ok "[보안] 인증 토큰 상수시간 비교 사용 확인"
    fi
    if echo "$TG_SRC" | grep -q 'rel_url.query.get("token"'; then
      warn "[보안] 대시보드 토큰을 URL 쿼리(?token=)로 허용 — 로그/히스토리 유출 위험. 헤더 전용 변경 권장 (감사 H3)"
    else
      ok "[보안] 대시보드 토큰 URL 쿼리 노출 없음"
    fi
  fi
fi

# ── (6) Browser Agent: HMAC 서명에 본문 포함 여부 (defense-in-depth) ──
if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^browser-agent$"; then
  BA_SRC=$(docker exec browser-agent cat /app/agent_server.py 2>/dev/null || echo "")
  if echo "$BA_SRC" | grep -q "verify_request_signature"; then
    if echo "$BA_SRC" | grep -qE 'body_hash|request\.body\(\)'; then
      ok "[보안] 요청 서명에 본문 해시 포함 — 본문 변조 방지"
    else
      info "[보안] 요청 서명이 본문 미포함(ts:method:path) — 윈도우 내 본문 재사용 가능. body_hash 포함 권장 (감사 H2)"
    fi
  fi
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
info "  전체 시작:         cd ~/OpenWebUI && docker compose up -d"
info "  전체 상태:         cd ~/OpenWebUI && docker compose ps"
info "  감사 로그:         cd ~/OpenWebUI && ./view-audit-log.sh"
info "  Twilio 로그:       docker logs -f twilio-bot"
info "  Telegram 시작:     cd ~/telegram-openwebui-bridge && docker compose up -d"
info "  Telegram 로그:     docker logs -f telegram-openwebui-bridge"
info "  대시보드 접속:     ssh -L 8445:localhost:8445 user@서버IP  →  http://localhost:8445/dashboard"
info "  Browser 로그:      docker logs -f browser-agent"
info "  메모리 확인:       curl -s http://localhost:8001/memory | python3 -m json.tool"
info "  Multi-Agent 확인:  curl -H \"Authorization: Bearer \$(grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env | cut -d= -f2-)\" http://localhost:8001/health/multi | python3 -m json.tool"
info "  히스토리 확인:     curl -H \"Authorization: Bearer \$(grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env | cut -d= -f2-)\" http://localhost:8001/history | python3 -m json.tool"
info "  모니터링 확인:     curl -H \"Authorization: Bearer \$(grep BROWSER_AGENT_API_KEY ~/OpenWebUI/.env | cut -d= -f2-)\" http://localhost:8001/monitors | python3 -m json.tool"
info "  파일 목록:         curl -s http://localhost:8001/files | python3 -m json.tool"
info "  Tool 수동 등록:    OWUI_KEY=\$(grep OPENWEBUI_API_KEY ~/OpenWebUI/.env | cut -d= -f2-)"
info "                     curl -X POST http://localhost:3000/api/v1/tools/create -H \"Authorization: Bearer \$OWUI_KEY\" ..."
info "  Browser 재설치:    docker stop browser-agent; docker rm browser-agent; sudo rm -rf ~/OpenWebUI/browser-agent"
info "                     bash setup-browser-agent-calendar.sh"
info "  Telegram 재설치:   docker stop telegram-openwebui-bridge; docker rm telegram-openwebui-bridge; sudo rm -rf ~/telegram-openwebui-bridge"
info "                     bash setup-telegram-bridge-calendar.sh"

exit $FAIL_COUNT
