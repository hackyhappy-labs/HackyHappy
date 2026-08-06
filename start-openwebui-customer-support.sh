#!/bin/bash
set -euo pipefail
# =============================================================================
# 프로젝트명: OpenWebUI RAG + Twilio AI 전화봇 설치 스크립트
# 제작자: <webmaster@vulva.sex>
# 버전: 1.1.0-보안강화 (다국어 지원 추가 - 한/영/일/중 자동 감지)
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
# ✅ 취약점 수정 (+5항목 = 총 21항목)
#    - 민감 입력 마스킹 (API Key/Token/비밀번호/PIN → Enter 후 **** 처리)
#    - 기본 비밀번호 제거 (빈 입력 시 openssl rand 자동 생성)
#    - PIN 잠금 영구 저장 (파일 기반 + 30분 자동 해제)
#    - voice-report TTS 인젝션 방지 (URL 파라미터 → 내부 저장소 조회)
#    - .gitignore/.dockerignore 자동 생성 (secrets/ .env 유출 방지)
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
# 0-0. 서비스 모드 선택 (고객전용 ↔ 개인용) — 가장 먼저 질문
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🎯 어떤 용도로 설치하시겠습니까?"
echo "└────────────────────────────────────────────┘"
echo "   1) 고객 상담용 (Customer)"
echo "      · 걸려온 전화를 '고객 상담'으로 응대"
echo "      · 상담원 0번 직통 연결 안내 ON"
echo "      · 인사말이 상담체 / 능동형 자동전화 OFF"
echo ""
echo "   2) 개인용 AI 비서 (Personal)"
echo "      · 걸려온 전화를 '지인 안부'로 따뜻하게 응대"
echo "      · 상담원 0번 안내 멘트 OFF (개인용은 안내 안 함)"
echo "      · 안부체 인사말 / 기억의 앵커 능동형 자동전화 사용 가능"
echo ""
echo "   ※ 설치 후에도 twilio-bot/ai_config.py 의 SERVICE_MODE 값만 바꾸면"
echo "      언제든 서로 전환할 수 있습니다."
echo ""
read -t 120 -p "선택 (1/2) [기본값: 1=고객상담용] (120초 내 Enter=1): " SERVICE_MODE_INPUT || true
SERVICE_MODE_INPUT=$(echo "$SERVICE_MODE_INPUT" | xargs)
if [ "$SERVICE_MODE_INPUT" = "2" ]; then
  SERVICE_MODE="personal"
  echo "   ✅ 개인용 AI 비서 모드로 설치합니다."
else
  SERVICE_MODE="customer"
  echo "   ✅ 고객 상담용 모드로 설치합니다."
fi

############################################
# 0-pre. 보안 입력 헬퍼 함수
############################################
read_secret() {
  # 민감 정보 입력 (확인 단계 포함):
  #   1) 입력 (타이핑은 화면에 숨김)
  #   2) 마스킹(****) + 글자 수 표시로 입력 확인
  #   3) Y/Enter=확정, n=재입력, s=실제값 확인 후 재확인
  # 사용법: VAR=$(read_secret "프롬프트: " [timeout])
  local prompt="$1"
  local timeout="${2:-120}"
  local value="" confirm masked
  while true; do
    value=""
    read -t "$timeout" -r -s -p "$prompt" value || true
    echo "" >&2
    value=$(echo "$value" | xargs)
    if [ -z "$value" ]; then
      # 빈 입력은 건너뛰기/자동생성 로직에 맡기기 위해 그대로 반환
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

# 등급값 일괄 적용 함수 (자동 감지 결과·수동 선택 모두 이 함수로 값을 세팅)
apply_performance_tier() {
  case "$1" in
    HIGH)
      PERFORMANCE="HIGH"; PERF_NAME="고성능 🚀"
      QDRANT_RETRIES=60; QDRANT_INTERVAL=3; TOOLS_RETRIES=60; TOOLS_INTERVAL=3
      WEBUI_RETRIES=90; WEBUI_INTERVAL=3
      MEMORY_QDRANT="1G"; MEMORY_TOOLS="2G"; MEMORY_WEBUI="4G"; MEMORY_TWILIO="256M"
      ;;
    MEDIUM_HIGH)
      PERFORMANCE="MEDIUM_HIGH"; PERF_NAME="중상급 💪"
      QDRANT_RETRIES=60; QDRANT_INTERVAL=4; TOOLS_RETRIES=60; TOOLS_INTERVAL=4
      WEBUI_RETRIES=90; WEBUI_INTERVAL=4
      MEMORY_QDRANT="768M"; MEMORY_TOOLS="1.5G"; MEMORY_WEBUI="3G"; MEMORY_TWILIO="256M"
      ;;
    MEDIUM)
      PERFORMANCE="MEDIUM"; PERF_NAME="중급 📊"
      QDRANT_RETRIES=90; QDRANT_INTERVAL=5; TOOLS_RETRIES=90; TOOLS_INTERVAL=5
      WEBUI_RETRIES=120; WEBUI_INTERVAL=5
      MEMORY_QDRANT="512M"; MEMORY_TOOLS="1G"; MEMORY_WEBUI="2G"; MEMORY_TWILIO="256M"
      ;;
    LOW)
      PERFORMANCE="LOW"; PERF_NAME="저사양 🐢"
      QDRANT_RETRIES=120; QDRANT_INTERVAL=6; TOOLS_RETRIES=120; TOOLS_INTERVAL=6
      WEBUI_RETRIES=180; WEBUI_INTERVAL=6
      MEMORY_QDRANT="384M"; MEMORY_TOOLS="768M"; MEMORY_WEBUI="1.5G"; MEMORY_TWILIO="256M"
      ;;
  esac
}

# 1) 자동 감지
if [ $CPU_CORES -ge 6 ] && [ $TOTAL_RAM -ge 16 ]; then
  apply_performance_tier "HIGH"
elif [ $CPU_CORES -ge 4 ] && [ $TOTAL_RAM -ge 8 ]; then
  apply_performance_tier "MEDIUM_HIGH"
elif [ $CPU_CORES -ge 2 ] && [ $TOTAL_RAM -ge 4 ]; then
  apply_performance_tier "MEDIUM"
else
  apply_performance_tier "LOW"
fi

echo ""
echo "┌────────────────────────────────────────────┐"
echo "📊 자동 감지된 성능: ${PERF_NAME}"
echo "└────────────────────────────────────────────┘"
echo "   메모리 할당: Qdrant(${MEMORY_QDRANT}), Tools(${MEMORY_TOOLS}), WebUI(${MEMORY_WEBUI}), Twilio봇(${MEMORY_TWILIO})"
echo ""

# 2) 수동 조정 기회 제공 (오픈소스 배포 시 자동 감지가 어긋나도 설치자가 바로잡을 수 있도록)
echo "이 등급으로 임베딩 모델·채팅 모델·메모리가 자동 설정됩니다:"
echo "   • 고성능   : 임베딩 mxbai-embed-large(1024) / 채팅 llama3.1:8b"
echo "   • 중상/중급: 임베딩 nomic-embed-text(768)  / 채팅 llama3.2:3b"
echo "   • 저사양   : 임베딩 all-minilm(384)        / 채팅 llama3.2:1b"
echo ""
echo "감지 결과가 실제 사양과 다르거나 더 가볍게/무겁게 쓰고 싶으면 조정할 수 있습니다."
echo "   1) 자동 감지 그대로 진행 (${PERF_NAME})"
echo "   2) 고성능 🚀      (RAM 16GB+ 권장)"
echo "   3) 중상급 💪      (RAM 8GB+ 권장)"
echo "   4) 중급 📊        (RAM 4GB+ 권장)"
echo "   5) 저사양 🐢      (가장 가볍게)"
read -t 120 -p "선택 (1~5) [기본값: 1=자동 감지] (120초 내 Enter=1): " PERF_CHOICE || true
PERF_CHOICE=$(echo "$PERF_CHOICE" | xargs)
case "$PERF_CHOICE" in
  2) apply_performance_tier "HIGH";        echo "   ✅ 수동 선택: 고성능 🚀" ;;
  3) apply_performance_tier "MEDIUM_HIGH"; echo "   ✅ 수동 선택: 중상급 💪" ;;
  4) apply_performance_tier "MEDIUM";      echo "   ✅ 수동 선택: 중급 📊" ;;
  5) apply_performance_tier "LOW";         echo "   ✅ 수동 선택: 저사양 🐢" ;;
  *) echo "   ✅ 자동 감지 그대로 진행: ${PERF_NAME}" ;;
esac

echo ""
echo "┌────────────────────────────────────────────┐"
echo "📊 적용된 성능 등급: ${PERF_NAME}"
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

# ── 🔑 Ollama를 모든 인터페이스(0.0.0.0)에 바인딩 ──────────────
#   기본 Ollama 는 127.0.0.1 에만 바인딩되어 Docker 컨테이너(twilio-bot 등)가
#   접근할 수 없다 → 임베딩(기억의 앵커·연락처 의미검색)이 더미 벡터로 폴백됨.
#   이 함수가 systemd override 또는 환경변수로 0.0.0.0 바인딩을 강제한다.
#   (WSL2·리눅스 공통. 컨테이너는 host-gateway 로 이 주소에 접근)
setup_ollama_bind() {
  # ⚠️ set -e 환경에서도 안전하도록 모든 실패를 흡수(|| true)한다.
  # 1) systemd 가 있으면 override 파일로 영구 설정
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q "ollama.service"; then
    sudo mkdir -p /etc/systemd/system/ollama.service.d 2>/dev/null || true
    printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:11434"\n' | \
      sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null 2>&1 || true
    sudo systemctl daemon-reload 2>/dev/null || true
    if sudo systemctl restart ollama 2>/dev/null; then
      echo "   ✅ Ollama 바인딩 설정: 0.0.0.0:11434 (systemd, 컨테이너 접근 가능)"
      sleep 3
      return 0
    fi
    # systemd restart 실패 → 아래 nohup 폴백으로 진행
  fi
  # 2) systemd 가 없거나 실패 → 기존 프로세스 종료 후 0.0.0.0 으로 재기동
  #    (pkill 은 대상이 없으면 종료코드 1 → set -e 방지 위해 || true)
  pkill -f "ollama serve" 2>/dev/null || true
  sleep 1
  OLLAMA_HOST=0.0.0.0:11434 nohup ollama serve > /tmp/ollama.log 2>&1 &
  sleep 5
  echo "   ✅ Ollama 바인딩 설정: 0.0.0.0:11434 (nohup, 컨테이너 접근 가능)"
  return 0
}

# ── 컨테이너→호스트 Ollama 접근 IP 자동 감지 ──────────────
#   docker0 브리지 게이트웨이 IP(보통 172.17.0.1)를 찾아 OLLAMA_BASE_URL 에 사용.
detect_ollama_host_ip() {
  local ip=""
  ip=$(ip -4 addr show docker0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1) || true
  [ -z "$ip" ] && ip=$(ip route 2>/dev/null | grep -oP 'default via \K\S+' | head -1) || true
  [ -z "$ip" ] && ip="172.17.0.1"
  echo "$ip"
  return 0
}

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
    sudo systemctl enable ollama 2>/dev/null || true
    # 🔑 컨테이너 접근을 위해 0.0.0.0 바인딩 강제 (재기동 포함)
    # set -e 환경 보호: 바인딩/모델체크 실패해도 설치는 계속되게 한다
    set +e
    setup_ollama_bind
    # 🆕 임베딩 모델도 성능 등급에 맞춰 자동 선택 (차원이 다르므로 EMBED_DIM 도 함께 확정).
    #    저사양=가벼운 384d / 중간=768d / 고사양=고품질 1024d
    if [ "$PERFORMANCE" = "HIGH" ]; then
      OLLAMA_EMBED_MODEL="mxbai-embed-large"; EMBED_DIM=1024
    elif [ "$PERFORMANCE" = "MEDIUM_HIGH" ] || [ "$PERFORMANCE" = "MEDIUM" ]; then
      OLLAMA_EMBED_MODEL="nomic-embed-text"; EMBED_DIM=768
    else
      OLLAMA_EMBED_MODEL="all-minilm"; EMBED_DIM=384
    fi
    if ! ollama list 2>/dev/null | grep -q "${OLLAMA_EMBED_MODEL%%:*}"; then
      echo "   📥 임베딩 모델 다운로드 중 (${OLLAMA_EMBED_MODEL}, ${EMBED_DIM}차원)..."
      ollama pull "$OLLAMA_EMBED_MODEL" || echo "⚠️ 임베딩 모델 다운로드 실패"
    fi
    # 🆕 채팅용 LLM 다운로드 — 이게 없으면 OpenWebUI 모델 선택란이 비어 보인다.
    #    성능 등급에 맞춰 모델 크기를 자동 선택한다.
    if [ "$PERFORMANCE" = "HIGH" ]; then
      OLLAMA_CHAT_MODEL="llama3.1:8b"
    elif [ "$PERFORMANCE" = "MEDIUM_HIGH" ] || [ "$PERFORMANCE" = "MEDIUM" ]; then
      OLLAMA_CHAT_MODEL="llama3.2:3b"
    else
      OLLAMA_CHAT_MODEL="llama3.2:1b"
    fi
    if ! ollama list 2>/dev/null | grep -q "${OLLAMA_CHAT_MODEL%%:*}"; then
      echo "   📥 채팅용 LLM 다운로드 중 (${OLLAMA_CHAT_MODEL}) — 잠시 걸릴 수 있습니다..."
      ollama pull "$OLLAMA_CHAT_MODEL" || echo "⚠️ 채팅 모델 다운로드 실패 (나중에 'ollama pull ${OLLAMA_CHAT_MODEL}' 로 재시도)"
    fi
    set -euo pipefail
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
    set +e
    curl -fsSL https://ollama.com/install.sh | sh
    sudo systemctl enable ollama 2>/dev/null || true
    # 🔑 컨테이너 접근을 위해 0.0.0.0 바인딩 강제 (설치 직후 재기동 포함)
    setup_ollama_bind
    # 🆕 임베딩 모델도 성능 등급에 맞춰 자동 선택 (차원이 다르므로 EMBED_DIM 도 함께 확정).
    if [ "$PERFORMANCE" = "HIGH" ]; then
      OLLAMA_EMBED_MODEL="mxbai-embed-large"; EMBED_DIM=1024
    elif [ "$PERFORMANCE" = "MEDIUM_HIGH" ] || [ "$PERFORMANCE" = "MEDIUM" ]; then
      OLLAMA_EMBED_MODEL="nomic-embed-text"; EMBED_DIM=768
    else
      OLLAMA_EMBED_MODEL="all-minilm"; EMBED_DIM=384
    fi
    echo "   📥 임베딩 모델 다운로드 중 (${OLLAMA_EMBED_MODEL}, ${EMBED_DIM}차원)..."
    ollama pull "$OLLAMA_EMBED_MODEL" || echo "⚠️ 임베딩 모델 다운로드 실패"
    # 🆕 채팅용 LLM 다운로드 — 이게 없으면 OpenWebUI 모델 선택란이 비어 보인다.
    if [ "$PERFORMANCE" = "HIGH" ]; then
      OLLAMA_CHAT_MODEL="llama3.1:8b"
    elif [ "$PERFORMANCE" = "MEDIUM_HIGH" ] || [ "$PERFORMANCE" = "MEDIUM" ]; then
      OLLAMA_CHAT_MODEL="llama3.2:3b"
    else
      OLLAMA_CHAT_MODEL="llama3.2:1b"
    fi
    echo "   📥 채팅용 LLM 다운로드 중 (${OLLAMA_CHAT_MODEL}) — 잠시 걸릴 수 있습니다..."
    ollama pull "$OLLAMA_CHAT_MODEL" || echo "⚠️ 채팅 모델 다운로드 실패 (나중에 'ollama pull ${OLLAMA_CHAT_MODEL}' 로 재시도)"
    set -euo pipefail
    USE_OLLAMA=true
  else
    USE_OLLAMA=false
  fi
fi

# ── 🔑 컨테이너가 접근할 Ollama 주소 확정 + 연결 테스트 ──────────
# (이 블록은 curl/ollama 실패가 잦으므로 set +e 로 감싸 스크립트 중단을 막는다)
set +e
OLLAMA_HOST_IP="172.17.0.1"
if [ "$USE_OLLAMA" = true ]; then
  OLLAMA_HOST_IP=$(detect_ollama_host_ip)
  echo "   🔎 컨테이너→Ollama 접근 IP: ${OLLAMA_HOST_IP}"
  # 실제로 그 IP:11434 로 임베딩이 되는지 테스트 (호스트에서)
  if curl -s --max-time 5 "http://${OLLAMA_HOST_IP}:11434/api/tags" >/dev/null 2>&1; then
    echo "   ✅ Ollama 접근 확인됨 (${OLLAMA_HOST_IP}:11434) — 기억의 앵커/의미검색 정상 작동"
  else
    echo "   ⚠️  ${OLLAMA_HOST_IP}:11434 접근 테스트 실패. 0.0.0.0 바인딩을 재시도합니다..."
    setup_ollama_bind
    if curl -s --max-time 5 "http://${OLLAMA_HOST_IP}:11434/api/tags" >/dev/null 2>&1; then
      echo "   ✅ 재시도 후 Ollama 접근 확인됨"
    else
      echo "   ⚠️  여전히 접근 불가. 설치는 계속되지만, 임베딩이 더미 벡터로 폴백될 수 있습니다."
      echo "      → 수동 해결: WSL2 안에서 'OLLAMA_HOST=0.0.0.0:11434 ollama serve' 로 실행하세요."
    fi
  fi
fi
set -euo pipefail

############################################
# 4. GPU 감지
############################################
if command -v nvidia-smi >/dev/null 2>&1; then
  OPEN_WEBUI_IMAGE="ghcr.io/open-webui/open-webui:cuda"
  echo "✅ NVIDIA GPU 감지 (CUDA)"
else
  OPEN_WEBUI_IMAGE="ghcr.io/open-webui/open-webui:v0.9.6"
  echo "ℹ️ GPU 없음 (CPU 모드)"
fi

############################################
# 5. Groq API Key
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔑 Groq API Key 설정 (선택사항)"
echo "└────────────────────────────────────────────┘"
GROQ_API_KEY=$(read_secret "🔑 Groq API Key 입력 (120초 내 Enter=건너뜀): " 120)
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

TWILIO_ACCOUNT_SID=$(read_secret "📞 Twilio Account SID 입력 (120초 내 Enter=건너뜀): " 120)

TWILIO_AUTH_TOKEN=$(read_secret "🔑 Twilio Auth Token 입력 (120초 내 Enter=건너뜀): " 120)

read -t 120 -p "📱 Twilio 전화번호 입력 ex) +18025550123 (120초 내 Enter=건너뜀): " TWILIO_PHONE_NUMBER || true
TWILIO_PHONE_NUMBER=$(echo "$TWILIO_PHONE_NUMBER" | xargs)

read -t 120 -p "📲 나의 실제 전화번호 입력 ex) +821012345678 (120초 내 Enter=건너뜀): " MY_PHONE_NUMBER || true
MY_PHONE_NUMBER=$(echo "$MY_PHONE_NUMBER" | xargs)

read -t 120 -p "🌐 서버 도메인 입력 ex) https://yourdomain.com (120초 내 Enter=건너뜀): " SERVER_DOMAIN || true
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
read -t 120 -p "   👤 관리자 이메일 (기본: admin@example.com | 120초 내 Enter=기본값): " OW_EMAIL || true
OW_EMAIL=$(echo "$OW_EMAIL" | xargs)
OW_EMAIL=${OW_EMAIL:-"admin@example.com"}

OW_PASSWORD=$(read_secret "   🔒 관리자 비밀번호 입력 (120초 내 Enter=자동생성): " 120)
if [ -n "$OW_PASSWORD" ]; then
  :
else
  OW_PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9!@#' | head -c 16)
  echo "   🔑 자동 생성된 비밀번호: $OW_PASSWORD"
  echo "   ⚠️  이 비밀번호를 반드시 안전한 곳에 저장하세요!"
fi
echo "   ✅ 관리자 계정 정보 저장됨"

############################################
# 6-2. OpenWebUI 앱 이름 설정 (추가기능)
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🏷️  OpenWebUI 앱 이름 설정 (화면에 표시될 이름)"
echo "└────────────────────────────────────────────┘"
echo "   브라우저 상단 및 사이드바에 표시되는 이름입니다."
echo "   최대 20글자, Enter=기본값(Open WebUI)"
echo ""
read -t 120 -p "   🏷️  앱 이름 입력 (최대 20자 | 120초 내 Enter=기본값): " WEBUI_CUSTOM_NAME || true
WEBUI_CUSTOM_NAME=$(echo "$WEBUI_CUSTOM_NAME" | xargs)
# 20글자 초과 시 자동 자름
if [ ${#WEBUI_CUSTOM_NAME} -gt 20 ]; then
  WEBUI_CUSTOM_NAME="${WEBUI_CUSTOM_NAME:0:20}"
  echo "   ⚠️  20글자 초과 → 자동으로 잘림: ${WEBUI_CUSTOM_NAME}"
fi
WEBUI_CUSTOM_NAME=${WEBUI_CUSTOM_NAME:-"Open WebUI"}
# 특수문자 필터링 ($, `, ", \, ! 제거) → heredoc/YAML 깨짐 방지
WEBUI_CUSTOM_NAME=$(echo "$WEBUI_CUSTOM_NAME" | tr -d '$`"\\!')
WEBUI_CUSTOM_NAME=${WEBUI_CUSTOM_NAME:-"Open WebUI"}
echo "   ✅ 앱 이름 설정됨: ${WEBUI_CUSTOM_NAME}"


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

# BOT_MODE=2 인데 Groq Key 없으면 자동으로 1로 전환
if [ "$BOT_MODE" = "2" ] && [ -z "$GROQ_API_KEY" ]; then
  echo "   ⚠️  경고: BOT_MODE=2 (Groq 직결) 선택했지만 Groq API Key가 없습니다."
  echo "   🔄  자동으로 BOT_MODE=1 (OpenWebUI 경유)로 전환합니다."
  BOT_MODE=1
fi

# BOT_MODE=1 인데 OpenWebUI도 없으면 경고
if [ "$BOT_MODE" = "1" ] && [ -z "$GROQ_API_KEY" ]; then
  echo "   ⚠️  경고: Groq API Key가 없습니다. OpenWebUI 모델만 사용 가능합니다."
fi

############################################
# 7-1. 보안 설정 (PIN + 연락처)
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔒 보안 설정"
echo "└────────────────────────────────────────────┘"

# 관리자 명령 PIN (6자리) — 민감 명령(연락처 저장·전화·문자·예약) 실행 시 통화에서 입력.
# 직접 6자리 숫자를 입력하거나, 그냥 Enter 를 누르면 자동 생성됩니다.
while true; do
  ADMIN_PIN=$(read_secret "   🔢 관리자 PIN 6자리 입력 (숫자만 | 120초 내 Enter=자동생성): " 120)
  if [ -z "$ADMIN_PIN" ]; then
    # Enter → 무작위 6자리 자동 생성
    ADMIN_PIN=$(od -An -N3 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')
    ADMIN_PIN=$(printf '%06d' $(( ${ADMIN_PIN:-0} % 1000000 )) 2>/dev/null || echo "519740")
    echo "   🎲 PIN 자동 생성됨: ${ADMIN_PIN}  (통화 시 이 번호를 입력하세요. 꼭 메모해 두세요)"
    break
  elif echo "$ADMIN_PIN" | grep -Eq '^[0-9]{6}$'; then
    echo "   ✅ 관리자 PIN 설정 완료 (6자리)"
    break
  else
    echo "   ⚠️  PIN 은 숫자 6자리여야 합니다. 다시 입력해 주세요."
  fi
done
echo "   ℹ️  통화 인증: 등록된 관리자 번호 + 민감 명령 시 PIN 6자리 확인"

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

echo ""
echo "📚 RAG 검색 모드 선택:"
echo "   1) 통합 검색 — 전화/웹/텔레그램 모두 같은 문서 검색 (개인/소규모)"
echo "   2) 분리 검색 — 전화는 전용 문서만 검색 (고객상담용)"
# 서비스 모드에 맞춰 기본값 자동 추천 (개인용→통합, 고객용→분리)
if [ "$SERVICE_MODE" = "personal" ]; then
  RAG_DEFAULT="1"; RAG_DEFAULT_NAME="통합 검색(개인용 권장)"
else
  RAG_DEFAULT="2"; RAG_DEFAULT_NAME="분리 검색(고객상담용 권장)"
fi
read -t 120 -p "선택 (1/2, 기본=${RAG_DEFAULT} ${RAG_DEFAULT_NAME}): " RAG_MODE || true
RAG_MODE=$(echo "$RAG_MODE" | xargs)
RAG_MODE=${RAG_MODE:-$RAG_DEFAULT}
if [ "$RAG_MODE" = "2" ]; then
  RAG_UNIFIED_SEARCH="false"
  echo "   ✅ 분리 검색 모드 — 전화는 openapi_rag 전용 문서만 검색"
else
  RAG_UNIFIED_SEARCH="true"
  echo "   ✅ 통합 검색 모드 — 전체 문서 통합 검색"
fi

############################################
# 8. 작업 디렉토리 초기화
############################################
BASE_DIR="$HOME/OpenWebUI"
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
# 🆕 임베딩 차원 (성능별 임베딩 모델에 맞춰 자동 설정. Ollama 미사용 시 기본 768)
EMBED_DIM=${EMBED_DIM:-768}
OLLAMA_EMBED_MODEL=${OLLAMA_EMBED_MODEL:-nomic-embed-text}
EOF

if [ "$USE_OLLAMA" = true ]; then
cat >> .env <<EOF
OLLAMA_BASE_URL=http://${OLLAMA_HOST_IP}:11434
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
echo "" >> .env
echo "# 📼 통화 녹음 & PDF 보고서 (true=활성화, false=비활성화)" >> .env
echo "ENABLE_CALL_RECORDING=false" >> .env
echo "ENABLE_PDF_REPORT=false" >> .env

############################################
# 🎙️ 진짜 실시간(Media Streams) 모드 설정
############################################
echo "" >> .env
echo "# 🎙️ 진짜 실시간 대화 (말 도중 끼어들기). true=켬" >> .env

REALTIME_MODE_INPUT="false"
DEEPGRAM_API_KEY=""
ELEVENLABS_API_KEY=""
TTS_VOICE_INPUT="21m00Tcm4TlvDq8ikWAM"

if [ "$USE_TWILIO" = true ]; then
  echo ""
  echo "┌────────────────────────────────────────────┐"
  echo "🎙️  진짜 실시간 AI 대리통화 (선택)"
  echo "└────────────────────────────────────────────┘"
  echo "   ▸ 켜면: 말하는 도중에도 AI가 즉시 끼어들어 반응하는 진짜 실시간 통화"
  echo "   ▸ 필요: Deepgram(STT) + ElevenLabs(TTS) API 키 (유료)"
  echo "   ▸ 끄면: 기존 방식(한 문장씩 주고받기)으로 동작 — 나중에 밸브로 켤 수 있음"
  echo "   ▸ STT/TTS 제공자·음성은 나중에 OpenWebUI 밸브에서 변경 가능"
  echo ""
  read -p "🎙️ 진짜 실시간 모드를 켜시겠습니까? (y/N): " RT_ON
  RT_ON=${RT_ON:-N}
  if [[ "$RT_ON" =~ ^[Yy]$ ]]; then
    REALTIME_MODE_INPUT="true"
    DEEPGRAM_API_KEY=$(read_secret "🔑 Deepgram API Key 입력 (STT, 120초 내 Enter=건너뜀): " 120)
    ELEVENLABS_API_KEY=$(read_secret "🔑 ElevenLabs API Key 입력 (TTS, 120초 내 Enter=건너뜀): " 120)
    read -p "🔊 ElevenLabs 음성 ID (Enter=기본 Rachel): " TTS_VOICE_IN
    TTS_VOICE_INPUT=${TTS_VOICE_IN:-21m00Tcm4TlvDq8ikWAM}
    if [ -z "$DEEPGRAM_API_KEY" ] || [ -z "$ELEVENLABS_API_KEY" ]; then
      echo "   ⚠️  키가 비어 있어도 진행합니다. 나중에 밸브(OpenWebUI 도구)에서 입력하면 됩니다."
    fi
    echo "   ✅ 진짜 실시간 모드 활성화"
  else
    echo "   ⭐️ 실시간 모드 꺼짐 (기존 방식). 나중에 .env 의 REALTIME_MODE=true 로 켤 수 있습니다."
  fi
fi

############################################
# 📨 텔레그램 안부·통화 보고 알림 설정 (선택)
############################################
TELEGRAM_BOT_TOKEN_INPUT=""
TELEGRAM_CHAT_ID_INPUT=""
echo ""
echo "┌────────────────────────────────────────────┐"
echo "📨  텔레그램 통화 보고 알림 (선택)"
echo "└────────────────────────────────────────────┘"
echo "   ▸ 켜면: 안부전화·수신전화 보고가 문자(SMS)뿐 아니라 텔레그램으로도 옵니다."
echo "   ▸ 준비물: ① 텔레그램 봇 토큰  ② 내 채팅 ID"
echo "       ① @BotFather 에게 /newbot → 봇 토큰 발급 (1234:ABC... 형태)"
echo "       ② 만든 봇에게 아무 메시지나 보낸 뒤, 아래 주소에서 chat id 확인:"
echo "          https://api.telegram.org/bot<봇토큰>/getUpdates 의 \"chat\":{\"id\":숫자}"
echo "   ▸ 건너뛰면: 문자(SMS) 보고만 옵니다. 나중에 .env 에 넣어도 됩니다."
echo ""
read -p "📨 텔레그램 보고 알림을 설정하시겠습니까? (y/N): " TG_ON
TG_ON=${TG_ON:-N}
if [[ "$TG_ON" =~ ^[Yy]$ ]]; then
  TELEGRAM_BOT_TOKEN_INPUT=$(read_secret "🔑 텔레그램 봇 토큰 입력 (120초 내 Enter=건너뜀): " 120)
  read -p "🆔 내 채팅 ID 입력 (여러 명은 쉼표로 구분 | Enter=건너뜀): " TELEGRAM_CHAT_ID_INPUT
  if [ -n "$TELEGRAM_BOT_TOKEN_INPUT" ] && [ -n "$TELEGRAM_CHAT_ID_INPUT" ]; then
    echo "   ✅ 텔레그램 보고 설정됨"
    echo "   ⚠️  봇에게 먼저 '/start' 또는 아무 메시지를 보내야 봇이 당신에게 알림을 보낼 수 있습니다!"
  else
    echo "   ⭐️ 값이 비어 텔레그램 보고는 비활성 (문자 보고만 옴). 나중에 .env 에 추가 가능."
  fi
else
  echo "   ⭐️ 텔레그램 보고 건너뜀 (문자 보고만 옴)."
fi

# wss 도메인 자동 유도 (https→wss). SERVER_DOMAIN 이 https 가 아니면 비워두고 봇이 처리.
REALTIME_WSS_DOMAIN_VAL=""
case "$SERVER_DOMAIN" in
  https://*) REALTIME_WSS_DOMAIN_VAL="wss://${SERVER_DOMAIN#https://}" ;;
  http://*)  REALTIME_WSS_DOMAIN_VAL="ws://${SERVER_DOMAIN#http://}" ;;
esac

{
  echo "REALTIME_MODE=${REALTIME_MODE_INPUT}"
  echo "REALTIME_WSS_DOMAIN=${REALTIME_WSS_DOMAIN_VAL}"
  echo "REALTIME_STREAM_PATH=/twilio-stream"
  echo ""
  echo "# 🎙️ STT/TTS 제공자·키 (밸브에서 변경 가능)"
  echo "STT_PROVIDER=deepgram"
  echo "DEEPGRAM_API_KEY=${DEEPGRAM_API_KEY}"
  echo "STT_MODEL=nova-2"
  echo "TTS_PROVIDER=elevenlabs"
  echo "ELEVENLABS_API_KEY=${ELEVENLABS_API_KEY}"
  echo "TTS_VOICE=${TTS_VOICE_INPUT}"
  echo "TTS_MODEL=eleven_flash_v2_5"
  echo ""
  echo "# 📨 텔레그램 통화 보고 알림 (안부전화·수신전화 보고를 텔레그램으로도 전송)"
  echo "TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN_INPUT}"
  echo "TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID_INPUT}"
  echo ""
  echo "# 🤫 실시간 귓속말 전용 텔레그램 봇 (선택)"
  echo "#   텔레그램 브릿지(setup-telegram-bridge)를 함께 쓰면 봇 토큰 충돌(409)이 나므로,"
  echo "#   @BotFather 로 귓속말 전용 봇을 따로 만들어 아래에 넣으면 충돌 없이 작동합니다."
  echo "#   비워두면 위 TELEGRAM_BOT_TOKEN 을 공유합니다(브릿지 미사용 시 무방)."
  echo "WHISPER_TELEGRAM_BOT_TOKEN="
  echo "WHISPER_TELEGRAM_CHAT_ID="
} >> .env

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

# Secret → 환경변수 브릿지 엔트리포인트 생성
cat > "$BASE_DIR/secrets/entrypoint-secrets.sh" << 'SECEOF'
#!/bin/sh
# Docker Secrets → 환경변수 브릿지
# /run/secrets/ 파일을 읽어 환경변수로 export 후 원래 CMD 실행
# ⚠️ cat 실패 시 기존 환경변수를 덮어쓰지 않음 (Permission denied 방어)
_try_secret() { _v=$(cat "$1" 2>/dev/null) && [ -n "$_v" ] && export "$2=$_v"; }
_try_secret /run/secrets/twilio_auth_token TWILIO_AUTH_TOKEN
_try_secret /run/secrets/api_secret        API_SECRET
_try_secret /run/secrets/groq_api_key      OPENAI_API_KEY
_try_secret /run/secrets/admin_pin         ADMIN_PIN
_try_secret /run/secrets/webui_secret_key  WEBUI_SECRET_KEY
exec "$@"
SECEOF

# Secret 파일 권한 잠금 (모든 파일 생성 완료 후)
chmod 700 "$BASE_DIR/secrets"
chmod 644 "$BASE_DIR/secrets/"* 2>/dev/null
chmod +x "$BASE_DIR/secrets/"*.sh 2>/dev/null || true
# secrets 소유자를 컨테이너 UID와 일치
chown -R 1001:1001 "$BASE_DIR/secrets" 2>/dev/null || \
    sudo chown -R 1001:1001 "$BASE_DIR/secrets" 2>/dev/null || true

echo "   ✅ Docker Secrets 생성 완료 ($(ls "$BASE_DIR/secrets/"*.* 2>/dev/null | wc -l)개 파일)"
echo "   📁 경로: $BASE_DIR/secrets/ (chmod 700)"


############################################
# 10. Twilio 봇 파일 생성
############################################
cat > twilio-bot/requirements.txt <<'EOF'
# ⚠️ 최소 버전: CVE 패치 기준
# CVE-2026-27205 (CVSS 5.3) Flask 세션 캐시 정보 노출
flask>=3.1.3
twilio>=8.10.0
# CVE-2024-47081 (netrc 자격증명 유출) / CVE-2026-25645 패치
requests>=2.34.2
# CVE-2026-21441 (urllib3 DoS 압축폭탄/리다이렉트)
urllib3>=2.6.3
python-dotenv>=1.0.0
# CVE-2024-6827 (CVSS 7.5) HTTP Request Smuggling
# CVE-2024-1135 (CVSS 7.5) TE.CL Request Smuggling
gunicorn>=23.0.0
qdrant-client>=1.7.0
ollama>=0.1.7
fpdf2>=2.7.6
EOF

cat > twilio-bot/twilio_bot.py <<'PYEOF'
import hmac
from flask import Flask, request, Response, jsonify
from twilio.twiml.voice_response import VoiceResponse, Gather, Dial
from twilio.twiml.messaging_response import MessagingResponse
from twilio.rest import Client
import requests, os, json, time, threading, re, hmac
import ipaddress
from datetime import datetime
from functools import wraps

app = Flask(__name__)

# ── 보안: 정확한 사설망(RFC1918) + 루프백 판별 ──
def _is_private_ip(ip):
    """문자열 prefix 대신 ipaddress 모듈로 정확히 사설망/루프백 여부 판별"""
    if ip in ("localhost",):
        return True
    try:
        addr = ipaddress.ip_address(ip)
        return addr.is_private or addr.is_loopback
    except ValueError:
        return False

# ── 환경 변수 ──────────────────────────────────
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN  = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_PHONE       = os.getenv("TWILIO_PHONE_NUMBER", "")
MY_PHONE           = os.getenv("MY_PHONE_NUMBER", "")
SERVER_DOMAIN      = os.getenv("SERVER_DOMAIN", "http://localhost")
BOT_MODE           = os.getenv("BOT_MODE", "2")
OPENWEBUI_URL      = os.getenv("OPENWEBUI_URL", "http://open-webui:8080")
OPENWEBUI_API_KEY  = os.getenv("OPENWEBUI_API_KEY", "")
MODEL              = os.getenv("MODEL", "llama-3.3-70b-versatile")
GROQ_API_KEY       = os.getenv("OPENAI_API_KEY", "")
GROQ_API_URL       = "https://api.groq.com/openai/v1/chat/completions"

# ── 🎙️ 진짜 실시간(Media Streams) 모드 ──────────────────────────
#   REALTIME_MODE=true 면 통화 시 turn-based(Gather) 대신
#   <Connect><Stream> 으로 realtime-voice 서버(wss)에 오디오를 넘긴다.
#   말하는 중간에도 끼어들기(barge-in)가 되는 진짜 실시간 대화.
REALTIME_MODE      = os.getenv("REALTIME_MODE", "false").lower() == "true"
# wss 도메인: SERVER_DOMAIN(https://...) → wss://... 로 변환하거나 명시적 지정
def _derive_wss_domain():
    explicit = os.getenv("REALTIME_WSS_DOMAIN", "").strip()
    if explicit:
        return explicit.rstrip("/")
    d = (SERVER_DOMAIN or "").strip().rstrip("/")
    if d.startswith("https://"):
        return "wss://" + d[len("https://"):]
    if d.startswith("http://"):
        return "ws://" + d[len("http://"):]
    return "wss://" + d
REALTIME_WSS_DOMAIN = _derive_wss_domain()
REALTIME_STREAM_PATH = os.getenv("REALTIME_STREAM_PATH", "/twilio-stream")

def build_stream_twiml(name="", number="", direction="inbound", greeting="", system_prompt=""):
    """<Connect><Stream> TwiML 생성 — realtime-voice 서버로 양방향 오디오 연결.
       customParameters 로 통화 맥락(이름/번호/첫인사)을 서버에 전달."""
    from twilio.twiml.voice_response import VoiceResponse as _VR, Connect as _Connect
    vr = _VR()
    connect = _Connect()
    stream = connect.stream(url=f"{REALTIME_WSS_DOMAIN}{REALTIME_STREAM_PATH}")
    if name:
        stream.parameter(name="name", value=name)
    if number:
        stream.parameter(name="number", value=number)
    stream.parameter(name="direction", value=direction)
    if greeting:
        stream.parameter(name="greeting", value=greeting)
    if system_prompt:
        stream.parameter(name="system_prompt", value=system_prompt)
    vr.append(connect)
    return str(vr)

# ── 보안 설정 ──────────────────────────────────
ADMIN_NUMBERS      = [n.strip() for n in os.getenv("ADMIN_NUMBERS", MY_PHONE).split(",") if n.strip()]
ADMIN_PIN          = os.getenv("ADMIN_PIN", "123456")
BLOCKED_NUMBERS    = [n.strip() for n in os.getenv("BLOCKED_NUMBERS", "").split(",") if n.strip()]
PIN_MAX_FAIL       = 3
PIN_LOCKOUT_SECONDS = 1800  # 30분 잠금 후 자동 해제
PIN_LOCKOUT_FILE   = "/app/data/pin_lockout.json"

def _load_pin_data():
    try:
        if os.path.exists(PIN_LOCKOUT_FILE):
            with open(PIN_LOCKOUT_FILE, "r") as f:
                return json.load(f)
    except Exception:
        pass
    return {}

def _save_pin_data(data):
    try:
        os.makedirs(os.path.dirname(PIN_LOCKOUT_FILE), exist_ok=True)
        with open(PIN_LOCKOUT_FILE, "w") as f:
            json.dump(data, f)
        os.chmod(PIN_LOCKOUT_FILE, 0o600)
    except Exception as e:
        print(f"⚠️ PIN 잠금 저장 실패: {e}")

def record_pin_failure(caller):
    data = _load_pin_data()
    now = time.time()
    if caller not in data:
        data[caller] = {"count": 0, "locked_until": 0}
    entry = data[caller]
    if entry.get("locked_until", 0) > 0 and now > entry["locked_until"]:
        entry["count"] = 0
        entry["locked_until"] = 0
    entry["count"] += 1
    if entry["count"] >= PIN_MAX_FAIL:
        entry["locked_until"] = now + PIN_LOCKOUT_SECONDS
        print(f"🔒 PIN 잠금: {caller} ({PIN_LOCKOUT_SECONDS}초)")
    data[caller] = entry
    _save_pin_data(data)
    return entry["count"]

def reset_pin_failure(caller):
    data = _load_pin_data()
    if caller in data:
        data[caller] = {"count": 0, "locked_until": 0}
        _save_pin_data(data)

# ── Telegram 알림 설정 (선택 — Telegram 브릿지 설치 후 자동 활성화) ──────────
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID   = os.getenv("TELEGRAM_CHAT_ID", "")

# ── 🤫 실시간 귓속말 전용 텔레그램 봇 (충돌 방지) ──────────
#   텔레그램 브릿지(setup-telegram-bridge)와 같은 봇 토큰을 쓰면
#   getUpdates(폴링) vs webhook 충돌(409)이 난다. 그래서 귓속말은
#   전용 토큰(WHISPER_TELEGRAM_BOT_TOKEN)을 우선 사용하고,
#   없으면 기존 TELEGRAM_BOT_TOKEN 으로 폴백한다.
#   ⚠️ 폴백(공용 토큰)일 때 브릿지도 같은 토큰으로 돌면 충돌할 수 있으므로,
#      브릿지를 쓴다면 반드시 전용 토큰을 설정하는 것을 권장.
WHISPER_TG_TOKEN   = os.getenv("WHISPER_TELEGRAM_BOT_TOKEN", "") or TELEGRAM_BOT_TOKEN
WHISPER_TG_CHAT_ID = os.getenv("WHISPER_TELEGRAM_CHAT_ID", "") or TELEGRAM_CHAT_ID
# 전용 토큰이 따로 지정됐는지(브릿지와 분리됐는지) 여부
WHISPER_TG_DEDICATED = bool(os.getenv("WHISPER_TELEGRAM_BOT_TOKEN", "").strip())

# ── 통화 녹음 & PDF 보고서 (ON/OFF 토글 가능) ──────────
ENABLE_CALL_RECORDING = os.getenv("ENABLE_CALL_RECORDING", "false").lower() == "true"
ENABLE_PDF_REPORT     = os.getenv("ENABLE_PDF_REPORT", "false").lower() == "true"
RECORDINGS_DIR        = "/app/data/recordings"
REPORTS_DIR           = "/app/data/reports"
os.makedirs(RECORDINGS_DIR, exist_ok=True)
os.makedirs(REPORTS_DIR, exist_ok=True)
print(f"📼 통화 녹음: {'✅ 활성화' if ENABLE_CALL_RECORDING else '⭐ 비활성화'}")
print(f"📄 PDF 보고서: {'✅ 활성화' if ENABLE_PDF_REPORT else '⭐ 비활성화'}")

def send_to_telegram(text):
    """Twilio 통화 결과를 Telegram으로 전달 (토큰/채팅ID 설정 시만 작동)"""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        # 진단: 왜 안 보내지는지 로그로 남긴다 (값 누락이 가장 흔한 원인)
        _miss = []
        if not TELEGRAM_BOT_TOKEN: _miss.append("TELEGRAM_BOT_TOKEN")
        if not TELEGRAM_CHAT_ID:   _miss.append("TELEGRAM_CHAT_ID")
        print(f"ℹ️ Telegram 보고 비활성 — .env 에 {', '.join(_miss)} 미설정 (문자 보고만 발송됨)")
        return False
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        # 여러 관리자에게 동시 전송
        chat_ids = [cid.strip() for cid in TELEGRAM_CHAT_ID.split(",") if cid.strip()]
        sent = 0
        for cid in chat_ids:
            resp = requests.post(url, json={"chat_id": cid, "text": text, "parse_mode": "HTML"}, timeout=5)
            # 텔레그램 API 응답 확인 (chat not found / 잘못된 토큰 등 진단)
            try:
                jr = resp.json()
                if jr.get("ok"):
                    sent += 1
                else:
                    desc = jr.get("description", "")
                    hint = ""
                    if "chat not found" in desc.lower():
                        hint = " → 봇에게 먼저 '/start'를 보냈는지, chat_id 가 맞는지 확인하세요."
                    elif "unauthorized" in desc.lower():
                        hint = " → 봇 토큰이 올바른지 확인하세요."
                    print(f"⚠️ Telegram 전송 거부 (chat_id={cid}): {desc}{hint}")
            except Exception:
                if resp.status_code == 200:
                    sent += 1
        if sent > 0:
            print(f"📨 Telegram 보고 전송 완료 ({sent}명)")
            return True
        return False
    except Exception as e:
        # 보안: 에러 메시지에서 Bot Token 마스킹 (requests 라이브러리가 URL 전체를 traceback에 포함할 수 있음)
        err_msg = str(e)
        if TELEGRAM_BOT_TOKEN and TELEGRAM_BOT_TOKEN in err_msg:
            err_msg = err_msg.replace(TELEGRAM_BOT_TOKEN, TELEGRAM_BOT_TOKEN[:8] + "***")
        print(f"⚠️ Telegram 알림 전송 실패 (무시): {err_msg}")
        return False

# ═══════════════════════════════════════════════════════════════════════
# 🔟 실시간 귓속말 (AI 대리통화 라이브 지시)  ★신규 기능★
#     제작자: <webmaster@vulva.sex>
#
#  기능: AI가 상대방과 통화하는 도중, 관리자가
#        ① 텔레그램  ② OpenWebUI 채팅/앱  으로 "이렇게 말해: ○○○"
#        라고 지시하면, AI가 다음 발화 턴에 그 지시를 자연스럽게 반영해서 말함.
#
#  구조:
#    - _active_calls : 지금 진행 중인 통화 목록 (call_sid → 정보)
#    - _whisper_queue: 통화별 대기 중인 관리자 지시 (call_sid → [지시,...])
#    - 매 발화 턴(/respond, /respond-out)에서 대기 지시를 꺼내
#      시스템 프롬프트 최상단에 최우선 주입 → AI가 그대로 반영.
#    - 텔레그램 롱폴링 스레드가 관리자 메시지를 실시간 수신.
#    - 인메모리 + /app/data/whispers.json 파일 백업 (재시작 대비).
# ═══════════════════════════════════════════════════════════════════════
import threading as _wthreading

WHISPER_FILE = "/app/data/whispers.json"
_whisper_lock = _wthreading.Lock()

# 진행 중 통화: call_sid -> {"name","number","direction","start","last_speech","last_ai"}
_active_calls = {}
# 대기 지시: call_sid -> ["이렇게 말해 준 내용", ...]
_whisper_queue = {}
# 텔레그램 롱폴링 offset (중복 수신 방지)
_tg_update_offset = 0

# 귓속말 지시를 AI 프롬프트로 감쌀 때 쓰는 틀 (언어별로 자연스럽게)
WHISPER_INSTRUCTION_TEMPLATE = os.getenv(
    "WHISPER_INSTRUCTION_TEMPLATE",
    "【관리자 실시간 지시 — 최우선】 지금 통화에서 관리자가 다음 내용을 전하라고 지시했습니다. "
    "이 지시를 당신의 다음 말에 자연스럽게 녹여서, 티나지 않게, 어색하지 않게 반영하세요. "
    "AI라거나 지시받았다는 티를 절대 내지 말고, 원래 대화 흐름에 맞춰 부드럽게 말하세요.\n"
    "지시 내용: \"{instruction}\""
)

def _load_whispers():
    """파일에서 대기 귓속말 복구 (재시작 대비)"""
    global _whisper_queue
    try:
        if os.path.exists(WHISPER_FILE):
            with open(WHISPER_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    _whisper_queue = data
    except Exception as e:
        print(f"⚠️ 귓속말 파일 로드 실패 (무시): {e}")

def _save_whispers():
    """대기 귓속말을 파일에 백업"""
    try:
        with open(WHISPER_FILE, "w", encoding="utf-8") as f:
            json.dump(_whisper_queue, f, ensure_ascii=False)
    except Exception as e:
        print(f"⚠️ 귓속말 파일 저장 실패 (무시): {e}")

def register_active_call(call_sid, name="", number="", direction="inbound"):
    """통화 시작 시 진행 중 목록에 등록"""
    if not call_sid:
        return
    with _whisper_lock:
        _active_calls[call_sid] = {
            "name": name or "상대방",
            "number": number or "",
            "direction": direction,  # inbound(수신) / outbound(안부·대리전화)
            "start": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "last_speech": "",
            "last_ai": "",
        }

def update_active_call(call_sid, last_speech=None, last_ai=None):
    """진행 중 통화의 최근 대화 갱신 (관리자가 모니터링용으로 조회)"""
    if not call_sid:
        return
    with _whisper_lock:
        c = _active_calls.get(call_sid)
        if not c:
            return
        if last_speech is not None:
            c["last_speech"] = last_speech
        if last_ai is not None:
            c["last_ai"] = last_ai

def unregister_active_call(call_sid):
    """통화 종료 시 정리"""
    if not call_sid:
        return
    with _whisper_lock:
        _active_calls.pop(call_sid, None)
        if call_sid in _whisper_queue:
            del _whisper_queue[call_sid]
            _save_whispers()

def add_whisper(call_sid, instruction):
    """관리자 귓속말 지시 추가 (다음 발화 턴에 반영됨)"""
    instruction = (instruction or "").strip()
    if not call_sid or not instruction:
        return False
    with _whisper_lock:
        _whisper_queue.setdefault(call_sid, []).append(instruction)
        _save_whispers()
    print(f"🤫 귓속말 접수 [{call_sid}]: {instruction[:40]}")
    return True

def pop_whispers(call_sid):
    """대기 중인 귓속말 지시를 모두 꺼내서(비우고) 프롬프트 조각으로 반환"""
    if not call_sid:
        return ""
    with _whisper_lock:
        items = _whisper_queue.get(call_sid, [])
        if not items:
            return ""
        combined = " / ".join(items)
        _whisper_queue[call_sid] = []
        _save_whispers()
    print(f"🎯 귓속말 반영 [{call_sid}]: {combined[:60]}")
    return WHISPER_INSTRUCTION_TEMPLATE.format(instruction=combined)

def list_active_calls():
    """진행 중 통화 목록 (관리자 조회용)"""
    with _whisper_lock:
        out = []
        for sid, c in _active_calls.items():
            pending = len(_whisper_queue.get(sid, []))
            out.append({
                "call_sid": sid,
                "name": c.get("name", ""),
                "number": c.get("number", ""),
                "direction": c.get("direction", ""),
                "start": c.get("start", ""),
                "last_speech": c.get("last_speech", ""),
                "last_ai": c.get("last_ai", ""),
                "pending_whispers": pending,
            })
        return out

def _resolve_whisper_target(target_hint):
    """관리자가 '이름'이나 '번호' 또는 아무것도 안 주면 → 대상 call_sid 결정.
       - 진행 중 통화가 1개면 그걸로 자동 선택.
       - 이름/번호 일부가 일치하면 그 통화.
       - 애매하면 None + 후보 목록."""
    calls = list_active_calls()
    if not calls:
        return None, []
    if not target_hint:
        if len(calls) == 1:
            return calls[0]["call_sid"], calls
        return None, calls
    hint = str(target_hint).strip().lower()
    for c in calls:
        if hint and (hint in (c["name"] or "").lower() or hint in (c["number"] or "").lower() or hint == c["call_sid"].lower()):
            return c["call_sid"], calls
    if len(calls) == 1:
        return calls[0]["call_sid"], calls
    return None, calls

# ── 텔레그램 실시간 귓속말 수신 (롱폴링 스레드) ──────────────────
# 관리자가 텔레그램 봇에게 아래 형식으로 보내면 실시간 지시로 처리:
#   "이렇게 말해: 곧 방문하겠다고 전해줘"
#   "귓속말: 목소리 톤을 좀 더 밝게 해줘"
#   "김철수 이렇게 말해: 다음 주에 다시 연락한다고 해"   (특정 통화 지정)
#   "/calls"  또는  "통화목록"                          (진행 중 통화 확인)
WHISPER_TRIGGER_WORDS = ["이렇게 말해", "이렇게말해", "귓속말", "whisper", "say:", "말해줘:"]

def _tg_send(chat_id, text):
    if not WHISPER_TG_TOKEN:
        return
    try:
        requests.post(
            f"https://api.telegram.org/bot{WHISPER_TG_TOKEN}/sendMessage",
            json={"chat_id": chat_id, "text": text, "parse_mode": "HTML"},
            timeout=5,
        )
    except Exception:
        pass

def _tg_is_admin_chat(chat_id):
    """등록된 관리자 채팅ID만 지시 허용 (미설정 시 모두 허용 안 함)"""
    if not WHISPER_TG_CHAT_ID:
        return False
    allowed = [c.strip() for c in WHISPER_TG_CHAT_ID.split(",") if c.strip()]
    return str(chat_id) in allowed

def _handle_telegram_command(chat_id, text):
    """텔레그램 관리자 명령 처리"""
    t = (text or "").strip()
    low = t.lower()

    # 진행 중 통화 목록
    if low in ("/calls", "/call", "통화목록", "통화 목록", "calls"):
        calls = list_active_calls()
        if not calls:
            _tg_send(chat_id, "📞 지금 진행 중인 통화가 없습니다.")
            return
        lines = ["📞 <b>진행 중 통화</b>"]
        for i, c in enumerate(calls, 1):
            d = "수신" if c["direction"] == "inbound" else "대리전화"
            lines.append(
                f"\n{i}. <b>{c['name']}</b> ({d}) {c['number']}"
                f"\n   🗣 상대: {c['last_speech'][:40] or '-'}"
                f"\n   🤖 AI: {c['last_ai'][:40] or '-'}"
                f"\n   ⏳ 대기 지시: {c['pending_whispers']}건"
            )
        lines.append("\n\n💡 지시하려면: <code>이렇게 말해: (전할 내용)</code>")
        _tg_send(chat_id, "\n".join(lines))
        return

    # 귓속말 트리거 확인
    matched = None
    for kw in WHISPER_TRIGGER_WORDS:
        idx = low.find(kw.lower())
        if idx != -1:
            matched = (kw, idx)
            break
    if not matched:
        return  # 일반 대화는 무시 (알림 전용 채팅과 공존)

    kw, idx = matched
    # 트리거 앞부분 = 대상 힌트(이름/번호), 뒷부분 = 지시 내용
    target_hint = t[:idx].strip(" :·-")
    instruction = t[idx + len(kw):].strip(" :·-\n")

    if not instruction:
        _tg_send(chat_id, "⚠️ 전할 내용이 비어 있습니다.\n예: <code>이렇게 말해: 곧 찾아뵙겠다고 전해줘</code>")
        return

    call_sid, calls = _resolve_whisper_target(target_hint)
    if not calls:
        _tg_send(chat_id, "📵 지금 진행 중인 통화가 없어 지시를 전달할 수 없습니다.")
        return
    if call_sid is None:
        # 여러 통화 → 대상 지정 필요
        names = ", ".join(f"{c['name']}" for c in calls)
        _tg_send(chat_id, f"❓ 진행 중 통화가 여러 개입니다: {names}\n대상을 앞에 붙여주세요.\n예: <code>김철수 이렇게 말해: (내용)</code>")
        return

    add_whisper(call_sid, instruction)
    tgt = next((c for c in calls if c["call_sid"] == call_sid), {})
    _tg_send(chat_id, f"✅ <b>{tgt.get('name','상대방')}</b>님과의 통화에 실시간 지시를 전달했습니다.\n🎯 곧 AI가 자연스럽게 반영해서 말합니다.\n💬 \"{instruction[:60]}\"")

def _telegram_whisper_poller():
    """텔레그램 롱폴링 — 관리자 실시간 지시 수신 (별도 스레드)"""
    global _tg_update_offset
    if not WHISPER_TG_TOKEN:
        print("ℹ️ 텔레그램 토큰 미설정 → 실시간 귓속말(텔레그램) 비활성 (OpenWebUI 도구로는 사용 가능)")
        return
    api = f"https://api.telegram.org/bot{WHISPER_TG_TOKEN}"

    # ── 충돌 방지 안전장치 ──────────────────────────────
    #   공용 토큰(브릿지와 공유)인데 이미 webhook 이 걸려 있으면
    #   getUpdates 가 409 Conflict 로 무한 오류난다. 이 경우 폴링을 켜지 않는다.
    #   (전용 토큰이면 이 검사를 건너뛰고 정상 진행)
    if not WHISPER_TG_DEDICATED:
        try:
            wi = requests.get(f"{api}/getWebhookInfo", timeout=10).json()
            hooked = bool((wi.get("result") or {}).get("url"))
            if hooked:
                print("⚠️ 텔레그램 귓속말: 이 봇 토큰에 webhook(브릿지)이 설정돼 있어 폴링을 시작하지 않습니다.")
                print("   → 귓속말 전용 봇을 따로 만들어 .env 의 WHISPER_TELEGRAM_BOT_TOKEN 에 넣으면 충돌 없이 작동합니다.")
                print("   (지금도 OpenWebUI '실시간 귓속말' 도구로는 정상 사용 가능)")
                return
        except Exception:
            pass  # 확인 실패 시엔 그냥 진행(폴링 시도)

    print("🤫 텔레그램 실시간 귓속말 수신 대기 시작...")
    # 시작 시 과거 미처리 업데이트는 건너뜀
    try:
        r = requests.get(f"{api}/getUpdates", params={"timeout": 0, "offset": -1}, timeout=10)
        res = r.json().get("result", [])
        if res:
            _tg_update_offset = res[-1]["update_id"] + 1
    except Exception:
        pass

    _conflict_count = 0
    while True:
        try:
            r = requests.get(
                f"{api}/getUpdates",
                params={"timeout": 50, "offset": _tg_update_offset, "allowed_updates": json.dumps(["message"])},
                timeout=60,
            )
            data = r.json()
            # 409 Conflict (다른 폴러/웹훅과 충돌) → 반복되면 폴링 중단
            if not data.get("ok") and data.get("error_code") == 409:
                _conflict_count += 1
                if _conflict_count >= 3:
                    print("⚠️ 텔레그램 귓속말: 409 충돌이 반복되어 폴링을 중단합니다(다른 봇/웹훅과 토큰 공유 추정).")
                    print("   → WHISPER_TELEGRAM_BOT_TOKEN 에 전용 봇 토큰을 설정하세요.")
                    return
                time.sleep(5)
                continue
            _conflict_count = 0
            for upd in data.get("result", []):
                _tg_update_offset = upd["update_id"] + 1
                msg = upd.get("message") or {}
                chat = msg.get("chat") or {}
                chat_id = chat.get("id")
                text = msg.get("text", "")
                if chat_id is None or not text:
                    continue
                if not _tg_is_admin_chat(chat_id):
                    # 미등록 채팅 → 자신의 chat_id 안내 (설정 편의)
                    _tg_send(chat_id, f"🔒 등록된 관리자만 지시할 수 있습니다.\n당신의 chat_id: <code>{chat_id}</code>\n(.env 의 WHISPER_TELEGRAM_CHAT_ID 또는 TELEGRAM_CHAT_ID 에 추가하세요)")
                    continue
                _handle_telegram_command(chat_id, text)
        except requests.exceptions.Timeout:
            continue
        except Exception as e:
            err = str(e)
            if WHISPER_TG_TOKEN and WHISPER_TG_TOKEN in err:
                err = err.replace(WHISPER_TG_TOKEN, WHISPER_TG_TOKEN[:8] + "***")
            print(f"⚠️ 텔레그램 폴링 오류 (5초 후 재시도): {err}")
            time.sleep(5)

# 부팅 시: 파일 복구 + 폴링 스레드 시작 (gunicorn workers=1 이라 안전)
_load_whispers()
_wthreading.Thread(target=_telegram_whisper_poller, daemon=True).start()

# ── 연락처 영구 저장 시스템 (Qdrant + JSON 이중 저장) ──────────
QDRANT_URL_CONTACTS = os.getenv("QDRANT_URL", "http://qdrant:6333")
CONTACTS_JSON_FILE  = "/app/data/contacts.json"  # JSON 백업 파일 (Ollama 없어도 영구 저장)
CONTACTS_COLLECTION = "contacts"
# 🆕 임베딩 차원 — 성능별 임베딩 모델에 맞춰 설치 스크립트가 EMBED_DIM 을 주입한다.
#    (all-minilm=384 / nomic-embed-text=768 / mxbai-embed-large=1024). 기본 768.
EMBED_DIM = int(os.getenv("EMBED_DIM", "768"))

# ── Qdrant 연락처 클라이언트 초기화 ──
_qdrant_contacts = None
def get_qdrant_contacts():
    global _qdrant_contacts
    if _qdrant_contacts is None:
        try:
            from qdrant_client import QdrantClient
            from qdrant_client.models import VectorParams, Distance
            _qdrant_contacts = QdrantClient(url=QDRANT_URL_CONTACTS)
            cols = [c.name for c in _qdrant_contacts.get_collections().collections]
            if CONTACTS_COLLECTION not in cols:
                _qdrant_contacts.create_collection(
                    collection_name=CONTACTS_COLLECTION,
                    vectors_config=VectorParams(size=EMBED_DIM, distance=Distance.COSINE),
                )
                print(f"✅ 연락처 Qdrant 컬렉션 생성: {CONTACTS_COLLECTION}")
            else:
                print(f"✅ 연락처 Qdrant 컬렉션 사용: {CONTACTS_COLLECTION}")
        except Exception as e:
            print(f"⚠️ Qdrant 연락처 초기화 실패: {e}")
            _qdrant_contacts = None
    return _qdrant_contacts

def _embed_contact(text):
    """연락처 텍스트 임베딩
    Ollama 있으면 실제 임베딩, 없으면 더미 벡터 반환
    → 어느 경우든 Qdrant에 저장 가능
    """
    try:
        import ollama
        OLLAMA_HOST = os.getenv("OLLAMA_BASE_URL", "http://172.17.0.1:11434")
        MODEL = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
        oc = ollama.Client(host=OLLAMA_HOST)
        resp = oc.embeddings(model=MODEL, prompt=text)
        print(f"✅ 임베딩 성공 (Ollama): {text[:20]}...")
        return resp["embedding"]
    except Exception as e:
        print(f"⚠️ Ollama 임베딩 실패 — 더미 벡터 사용: {e}")
        # Ollama 없어도 Qdrant에 저장 가능하도록 더미 벡터 반환
        # 벡터 검색은 안 되지만 이름/번호 데이터는 완벽하게 저장됨
        import hashlib
        h = hashlib.md5(text.encode()).digest()
        base = [((b / 255.0) - 0.5) * 2 for b in h]
        # EMBED_DIM 차원으로 확장 (성능별 임베딩 모델 크기에 맞춤)
        dummy = (base * (EMBED_DIM // len(base) + 1))[:EMBED_DIM]
        return dummy

def _contact_id(name):
    """이름 기반 고정 UUID (hashlib md5)"""
    import hashlib, uuid as _uuid
    return str(_uuid.UUID(hashlib.md5(name.encode()).hexdigest()))

def add_contact(name, number):
    """Qdrant 에 연락처 저장/업데이트"""
    # 🔒 이름 길이 제한 (모든 경로 공통 — API, 음성명령, 초기로드 등)
    if len(name) > 30:
        name = name[:30]
        print(f"⚠️ 연락처 이름 30자 초과 → 자동 잘림: {name}")
    try:
        from qdrant_client.models import PointStruct, Filter, FieldCondition, MatchValue
        qc = get_qdrant_contacts()
        if not qc:
            print(f"⚠️ Qdrant 미연결 — 연락처 저장 실패: {name}")
            return False
        # 기존 동일 이름 삭제 후 새로 저장 (업데이트)
        try:
            qc.delete(
                collection_name=CONTACTS_COLLECTION,
                points_selector=Filter(
                    must=[FieldCondition(key="name", match=MatchValue(value=name))]
                )
            )
        except Exception:
            pass
        embed_text = f"{name} {number}"
        # _embed_contact 는 Ollama 없어도 더미 벡터 반환 → 항상 Qdrant 저장 가능
        vector = _embed_contact(embed_text)
        qc.upsert(
            collection_name=CONTACTS_COLLECTION,
            points=[PointStruct(
                id=_contact_id(name),
                vector=vector,
                payload={"name": name, "number": number}
            )]
        )
        # 메모리 캐시 업데이트
        CONTACTS[name] = number
        # JSON 파일 이중 저장 (이중 보험)
        _save_contacts_json()
        print(f"📦 Qdrant 연락처 저장 완료: {name} ({number})")
        return True
    except Exception as e:
        print(f"⚠️ Qdrant 저장 실패 — JSON 폴백: {e}")
        # Qdrant 완전 장애 시 JSON에 저장
        CONTACTS[name] = number
        _save_contacts_json()
        return True

def delete_contact(name):
    """Qdrant 에서 연락처 삭제"""
    try:
        from qdrant_client.models import Filter, FieldCondition, MatchValue
        qc = get_qdrant_contacts()
        if not qc:
            return False
        qc.delete(
            collection_name=CONTACTS_COLLECTION,
            points_selector=Filter(
                must=[FieldCondition(key="name", match=MatchValue(value=name))]
            )
        )
        # 메모리 캐시에서도 삭제
        CONTACTS.pop(name, None)
        _save_contacts_json()
        print(f"🗑️ Qdrant 연락처 삭제: {name}")
        return True
    except Exception as e:
        print(f"⚠️ 연락처 삭제 실패: {e}")
        CONTACTS.pop(name, None)
        _save_contacts_json()
        return True

def search_contacts_qdrant(query, top_k=3):
    """Qdrant 의미 검색으로 연락처 찾기"""
    try:
        qc = get_qdrant_contacts()
        if not qc:
            return []
        vector = _embed_contact(query)
        if not vector:
            return []
        hits = qc.search(
            collection_name=CONTACTS_COLLECTION,
            query_vector=vector,
            limit=top_k,
            score_threshold=0.5
        )
        results = [{"name": h.payload["name"], "number": h.payload["number"], "score": h.score} for h in hits]
        if results:
            print(f"🔍 Qdrant 연락처 검색: '{query}' → {[r['name'] for r in results]}")
        return results
    except Exception as e:
        print(f"⚠️ Qdrant 연락처 검색 실패: {e}")
        return []

def _save_contacts_json():
    """연락처를 JSON 파일에 저장 (Ollama 없어도 영구 보존)"""
    try:
        os.makedirs(os.path.dirname(CONTACTS_JSON_FILE), exist_ok=True)
        with open(CONTACTS_JSON_FILE, "w", encoding="utf-8") as f:
            json.dump(CONTACTS, f, ensure_ascii=False, indent=2)
        os.chmod(CONTACTS_JSON_FILE, 0o600)
    except Exception as e:
        print(f"⚠️ JSON 연락처 저장 실패: {e}")

def _load_contacts_json():
    """JSON 파일에서 연락처 로드"""
    try:
        if os.path.exists(CONTACTS_JSON_FILE):
            with open(CONTACTS_JSON_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception as e:
        print(f"⚠️ JSON 연락처 로드 실패: {e}")
    return {}

def load_contacts():
    """Qdrant + JSON 에서 전체 연락처 로드 (메모리 캐시 초기화)"""
    data = {}
    # 환경변수 초기 연락처 (설치 시 입력한 값)
    try:
        env_contacts = json.loads(os.getenv("CONTACTS", "{}"))
        for name, number in env_contacts.items():
            add_contact(name, number)
            data[name] = number
    except Exception:
        pass
    # JSON 파일에서 로드 (Qdrant 실패 시 폴백)
    json_data = _load_contacts_json()
    data.update(json_data)
    # Qdrant 에서 전체 목록 로드 (JSON보다 우선)
    try:
        qc = get_qdrant_contacts()
        if qc:
            result = qc.scroll(
                collection_name=CONTACTS_COLLECTION,
                limit=10000,
                with_payload=True,
                with_vectors=False
            )
            for point in result[0]:
                name = point.payload.get("name", "")
                number = point.payload.get("number", "")
                if name and number:
                    data[name] = number
    except Exception as e:
        print(f"⚠️ Qdrant 연락처 로드 실패 — JSON 데이터 사용: {e}")
    # JSON 동기화
    if data:
        _save_contacts_json()
    print(f"📒 연락처 로드 완료: {len(data)}명 (Qdrant+JSON)")
    return data

# 메모리 캐시 (빠른 조회용 — Qdrant 데이터와 동기화)
CONTACTS = {}
def _init_contacts():
    global CONTACTS
    CONTACTS.update(load_contacts())
    print(f"📒 연락처 로드 완료: {list(CONTACTS.keys())}")
# Qdrant 초기화 + 연락처 로드 (백그라운드)
threading.Thread(target=lambda: (get_qdrant_contacts(), _init_contacts()), daemon=True).start()

# ═══════════════════════════════════════════════════════════════════════
# 🧠 기억의 앵커 (Memory Anchor)  ★신규 기능★
#     제작자: <webmaster@vulva.sex>
#
#  개념: 통화가 끝나면 대화 내용을 임베딩해 Qdrant 에 전화번호별로 저장한다.
#        (payload 에 phone_number/name/시간대/날씨/감정/주제/요약)
#        다음에 그 사람과 통화할 때, 지금 조건(전화번호+시간대+날씨)과
#        비슷한 과거 기억을 꺼내 AI 시스템 프롬프트에 주입 →
#        AI 가 "지난번에 ○○ 얘기하셨죠" 하고 자연스럽게 주제를 이어간다.
#
#  구조:
#    - 컬렉션 1개(call_memories) + payload 로 전화번호 구분 (방식 A)
#    - 텍스트 소스: 녹음 STT / 실시간 전사 / 통화 히스토리 (있는 것 사용)
#    - 임베딩: 연락처와 동일한 _embed_contact (Ollama nomic-embed-text, 768d)
# ═══════════════════════════════════════════════════════════════════════
MEMORY_COLLECTION = "call_memories"
MEMORY_JSON_FILE  = "/app/data/call_memories.json"   # 백업(검색 폴백)

def _memory_time_slot(dt=None):
    """시각 → 시간대 라벨 (앵커 조건)"""
    h = (dt or datetime.now()).hour
    if 5 <= h < 11:   return "아침"
    if 11 <= h < 14:  return "점심"
    if 14 <= h < 18:  return "오후"
    if 18 <= h < 22:  return "저녁"
    return "밤"

_weather_cache = {"ts": 0, "value": ""}
def _current_weather(city=None):
    """무료 wttr.in 으로 현재 날씨 한 단어(맑음/비/흐림 등). 실패해도 무해('')."""
    global _weather_cache
    now = time.time()
    if now - _weather_cache["ts"] < 1800 and _weather_cache["value"]:
        return _weather_cache["value"]   # 30분 캐시
    try:
        loc = city or os.getenv("WEATHER_CITY", "Seoul")
        r = requests.get(f"https://wttr.in/{loc}?format=%C", timeout=5)
        val = (r.text or "").strip()
        # 영문 날씨를 간단히 한글 키워드로 정규화
        low = val.lower()
        if "rain" in low or "drizzle" in low: val = "비"
        elif "snow" in low: val = "눈"
        elif "cloud" in low or "overcast" in low: val = "흐림"
        elif "clear" in low or "sunny" in low: val = "맑음"
        elif "fog" in low or "mist" in low: val = "안개"
        _weather_cache = {"ts": now, "value": val}
        return val
    except Exception:
        return ""

# ── Qdrant 기억 컬렉션 ──
_qdrant_memory = None
def get_qdrant_memory():
    global _qdrant_memory
    if _qdrant_memory is None:
        try:
            from qdrant_client import QdrantClient
            from qdrant_client.models import VectorParams, Distance
            _qdrant_memory = QdrantClient(url=QDRANT_URL_CONTACTS)
            cols = [c.name for c in _qdrant_memory.get_collections().collections]
            if MEMORY_COLLECTION not in cols:
                _qdrant_memory.create_collection(
                    collection_name=MEMORY_COLLECTION,
                    vectors_config=VectorParams(size=EMBED_DIM, distance=Distance.COSINE),
                )
                print(f"✅ 기억 앵커 Qdrant 컬렉션 생성: {MEMORY_COLLECTION}")
            else:
                print(f"✅ 기억 앵커 Qdrant 컬렉션 사용: {MEMORY_COLLECTION}")
        except Exception as e:
            print(f"⚠️ Qdrant 기억 초기화 실패: {e}")
            _qdrant_memory = None
    return _qdrant_memory

def _extract_memory_meta(conversation_text, name=""):
    """LLM 으로 대화에서 감정/주제/요약 추출. 실패 시 빈 값."""
    meta = {"emotion": "", "topic": "", "summary": ""}
    if not conversation_text.strip():
        return meta
    try:
        prompt = (
            f"다음은 {name or '상대방'}와의 통화 내용입니다. JSON 으로만 답하세요.\n"
            "형식: {\"emotion\": \"한 단어 감정(예: 밝음/우울/불안/평온)\", "
            "\"topic\": \"핵심 주제 한 구절\", \"summary\": \"한 문장 요약\"}\n\n"
            f"통화 내용:\n{conversation_text[:1500]}"
        )
        raw = get_ai_reply(prompt, "당신은 통화 내용을 분석하는 도우미입니다. 반드시 JSON 만 출력하세요.")
        raw = raw.strip()
        # ```json ... ``` 제거
        raw = re.sub(r"^```(json)?|```$", "", raw, flags=re.MULTILINE).strip()
        m = re.search(r"\{.*\}", raw, re.DOTALL)
        if m:
            parsed = json.loads(m.group(0))
            for k in meta:
                if parsed.get(k):
                    meta[k] = str(parsed[k])[:120]
    except Exception as e:
        print(f"⚠️ 기억 메타 추출 실패(무시): {e}")
    return meta

def save_call_memory(phone_number, name, conversation_text, extra_summary=""):
    """통화 종료 시 호출 → 대화를 임베딩해 Qdrant 에 전화번호별로 저장."""
    if not phone_number and not name:
        return False
    conversation_text = (conversation_text or "").strip()
    if len(conversation_text) < 10 and not extra_summary:
        return False   # 내용이 거의 없으면 저장 안 함
    try:
        from qdrant_client.models import PointStruct
        import uuid as _uuid
        qc = get_qdrant_memory()
        meta = _extract_memory_meta(conversation_text, name)
        if extra_summary and not meta["summary"]:
            meta["summary"] = extra_summary[:120]
        now = datetime.now()
        payload = {
            "phone_number": phone_number or "",
            "name": name or "",
            "date": now.strftime("%Y-%m-%d"),
            "time": now.strftime("%H:%M"),
            "time_slot": _memory_time_slot(now),
            "weather": _current_weather(),
            "emotion": meta["emotion"],
            "topic": meta["topic"],
            "summary": meta["summary"],
            "text": conversation_text[:2000],
        }
        # 임베딩 대상 텍스트(주제+요약+본문 일부)
        embed_text = f"{meta['topic']} {meta['summary']} {conversation_text[:500]}".strip()
        vector = _embed_contact(embed_text)   # 연락처와 동일 임베더 재사용
        if qc:
            qc.upsert(
                collection_name=MEMORY_COLLECTION,
                points=[PointStruct(id=str(_uuid.uuid4()), vector=vector, payload=payload)],
            )
        # JSON 백업(검색 폴백용)
        _append_memory_json(payload)
        print(f"🧠 기억 저장: {name or phone_number} | {meta['time_slot'] if False else payload['time_slot']} | {meta['emotion']} | {meta['topic'][:20]}")
        return True
    except Exception as e:
        print(f"⚠️ 기억 저장 실패(무시): {e}")
        return False

def _append_memory_json(payload):
    try:
        data = []
        if os.path.exists(MEMORY_JSON_FILE):
            with open(MEMORY_JSON_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
        data.append(payload)
        data = data[-500:]   # 최근 500개만 백업 유지
        with open(MEMORY_JSON_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
    except Exception:
        pass

def recall_memories(phone_number, name="", query_text="", match_conditions=True, top_k=3):
    """현재 통화 조건과 비슷한 과거 기억을 검색.
       - phone_number 로 필터(그 사람 기억만)
       - query_text 임베딩 유사도 + (선택) 시간대/날씨 조건 가산점
       반환: [{summary, topic, emotion, date, time_slot, weather, score}, ...]"""
    try:
        from qdrant_client.models import Filter, FieldCondition, MatchValue
        qc = get_qdrant_memory()
        if not qc:
            return _recall_from_json(phone_number, name, top_k)
        # 전화번호(없으면 이름)로 필터
        must = []
        if phone_number:
            must.append(FieldCondition(key="phone_number", match=MatchValue(value=phone_number)))
        elif name:
            must.append(FieldCondition(key="name", match=MatchValue(value=name)))
        flt = Filter(must=must) if must else None

        qvec = _embed_contact(query_text or f"{name} 통화")
        hits = qc.search(
            collection_name=MEMORY_COLLECTION,
            query_vector=qvec,
            query_filter=flt,
            limit=max(top_k * 2, 6),
            with_payload=True,
        )
        cur_slot = _memory_time_slot()
        cur_weather = _current_weather()
        scored = []
        for h in hits:
            p = h.payload or {}
            score = float(h.score or 0)
            # 앵커 조건 가산점: 같은 시간대/날씨면 점수 보정
            if match_conditions:
                if p.get("time_slot") == cur_slot: score += 0.15
                if cur_weather and p.get("weather") == cur_weather: score += 0.15
            scored.append((score, p))
        scored.sort(key=lambda x: x[0], reverse=True)
        out = []
        for score, p in scored[:top_k]:
            out.append({
                "summary": p.get("summary", ""), "topic": p.get("topic", ""),
                "emotion": p.get("emotion", ""), "date": p.get("date", ""),
                "time_slot": p.get("time_slot", ""), "weather": p.get("weather", ""),
                "score": round(score, 3),
            })
        return out
    except Exception as e:
        print(f"⚠️ 기억 검색 실패: {e}")
        return _recall_from_json(phone_number, name, top_k)

def _recall_from_json(phone_number, name, top_k):
    """Qdrant 실패 시 JSON 백업에서 최근 기억 반환(유사도 없이 최신순)."""
    try:
        if not os.path.exists(MEMORY_JSON_FILE):
            return []
        with open(MEMORY_JSON_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        filt = [d for d in data if (phone_number and d.get("phone_number") == phone_number)
                or (name and d.get("name") == name)]
        filt = filt[-top_k:][::-1]
        return [{"summary": d.get("summary",""), "topic": d.get("topic",""),
                 "emotion": d.get("emotion",""), "date": d.get("date",""),
                 "time_slot": d.get("time_slot",""), "weather": d.get("weather",""),
                 "score": 0} for d in filt]
    except Exception:
        return []

def build_memory_prompt(phone_number, name="", query_text=""):
    """회상 결과를 AI 시스템 프롬프트 조각으로 변환. 기억 없으면 ''."""
    mems = recall_memories(phone_number, name, query_text)
    if not mems:
        return ""
    lines = []
    for m in mems:
        when = f"{m['date']} {m['time_slot']}".strip()
        piece = m["summary"] or m["topic"]
        if not piece:
            continue
        extra = []
        if m["emotion"]: extra.append(f"그때 감정: {m['emotion']}")
        if m["weather"]: extra.append(f"날씨: {m['weather']}")
        tail = f" ({', '.join(extra)})" if extra else ""
        lines.append(f"- [{when}] {piece}{tail}")
    if not lines:
        return ""
    body = "\n".join(lines)
    return (
        "【기억의 앵커 — 과거 통화 회상】 아래는 이 사람과 예전에 나눈 대화 기록입니다. "
        "지금 대화 흐름에 자연스러울 때, 이 중 하나를 부드럽게 언급하며 대화를 그쪽으로 이어가세요. "
        "억지로 모두 꺼내지 말고, 자연스러운 한 가지만. AI라거나 기록을 봤다는 티는 내지 마세요.\n"
        f"{body}"
    )

# ═══════════════════════════════════════════════════════════════════════
# 🧠 기억의 앵커 — 능동형 자동전화 (제안형/자동형)  ★신규★
#   ai_config.py 의 MEMORY_AUTOCALL_* 설정으로 켜고 끈다. 기본 OFF.
#   주기적으로: 저장된 기억 중 "지금 시간대/날씨"와 조건이 맞는 사람을 찾아
#     - suggest 모드: 관리자에게 텔레그램/SMS 로 "전화 걸까요?" 제안
#     - auto 모드:    곧바로 안부전화 발신
#   안전장치: 발신 허용 시간대 / 쿨다운(사람당 N일) / 하루 최대 횟수
# ═══════════════════════════════════════════════════════════════════════
AUTOCALL_STATE_FILE = "/app/data/autocall_state.json"

def _autocall_load_state():
    try:
        if os.path.exists(AUTOCALL_STATE_FILE):
            with open(AUTOCALL_STATE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception:
        pass
    return {"last_called": {}, "daily": {"date": "", "count": 0}}

def _autocall_save_state(state):
    try:
        with open(AUTOCALL_STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False)
    except Exception:
        pass

def _autocall_within_hours():
    try:
        start, end = MEMORY_AUTOCALL_HOURS
        h = datetime.now().hour
        return start <= h < end
    except Exception:
        return False

def _autocall_daily_ok(state):
    today = datetime.now().strftime("%Y-%m-%d")
    d = state.get("daily", {})
    if d.get("date") != today:
        state["daily"] = {"date": today, "count": 0}
        return True
    return d.get("count", 0) < MEMORY_AUTOCALL_MAX_PER_DAY

def _autocall_cooldown_ok(state, phone):
    last = state.get("last_called", {}).get(phone)
    if not last:
        return True
    try:
        last_dt = datetime.strptime(last, "%Y-%m-%d %H:%M")
        return (datetime.now() - last_dt).days >= MEMORY_AUTOCALL_COOLDOWN_DAYS
    except Exception:
        return True

def _autocall_find_candidate():
    """저장된 기억을 훑어 지금 조건(시간대/날씨)과 맞는 (전화번호,이름,기억) 반환.
       조건은 MEMORY_AUTOCALL_MATCH 로 결정. 없으면 None."""
    cur_slot = _memory_time_slot()
    cur_weather = _current_weather()
    # JSON 백업에서 후보를 찾는다(가볍고 조건 필터가 쉬움)
    try:
        if not os.path.exists(MEMORY_JSON_FILE):
            return None
        with open(MEMORY_JSON_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return None
    # 최신 기억부터 검사
    for m in reversed(data):
        phone = m.get("phone_number", "")
        if not phone:
            continue
        ok = True
        if "time_slot" in MEMORY_AUTOCALL_MATCH and m.get("time_slot") != cur_slot:
            ok = False
        if "weather" in MEMORY_AUTOCALL_MATCH and cur_weather and m.get("weather") != cur_weather:
            ok = False
        if ok:
            return {"phone": phone, "name": m.get("name", ""), "memory": m,
                    "cur_slot": cur_slot, "cur_weather": cur_weather}
    return None

def _autocall_notify_admin(cand):
    """suggest 모드: 관리자에게 제안 알림 (텔레그램 + SMS)."""
    name = cand["name"] or cand["phone"]
    mem = cand["memory"]
    piece = mem.get("summary") or mem.get("topic") or "예전 대화"
    cond = []
    if cand["cur_slot"]: cond.append(cand["cur_slot"])
    if cand["cur_weather"]: cond.append(cand["cur_weather"])
    cond_txt = ", ".join(cond)
    msg = (f"🧠 <b>[기억의 앵커 — 자동전화 제안]</b>\n"
           f"👤 대상: {name} ({cand['phone']})\n"
           f"🕒 지금 조건: {cond_txt}\n"
           f"💬 과거 기억: {piece}\n"
           f"→ 지금 이분께 안부전화를 걸기 좋은 타이밍입니다.\n"
           f"   전화하려면: OpenWebUI 에서 \"{name}한테 안부전화 해줘\" 또는 앱에서 발신하세요.")
    try:
        if 'send_to_telegram' in globals():
            send_to_telegram(msg)
    except Exception:
        pass
    # SMS 로도 짧게 (관리자에게) — 텔레그램이 주력, SMS는 보조
    try:
        if MY_PHONE and TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN:
            sms = f"[자동전화 제안] {name}({cand['phone']}) - {cond_txt}. 과거: {piece[:40]}"
            _c = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
            _c.messages.create(to=MY_PHONE, from_=TWILIO_PHONE, body=sms)
    except Exception:
        pass
    print(f"🧠 자동전화 제안 알림: {name} ({cond_txt})")

def _autocall_place(cand):
    """auto 모드: 곧바로 안부전화 발신."""
    name = cand["name"] or "상대방"
    mem = cand["memory"]
    piece = mem.get("summary") or mem.get("topic") or ""
    greeting = f"{name}님, 안녕하세요. 문득 생각나서 안부전화 드렸어요."
    try:
        sid = make_call(cand["phone"], custom_message=greeting,
                        contact_name=name, mission=MEMORY_AUTOCALL_MISSION,
                        report_to=MY_PHONE)
        if sid:
            print(f"🧠 자동 안부전화 발신: {name} ({cand['phone']}) sid={sid}")
            try:
                if 'send_to_telegram' in globals():
                    send_to_telegram(f"🧠 <b>[기억의 앵커 — 자동전화 발신]</b>\n👤 {name} ({cand['phone']})\n💬 과거: {piece[:50]}")
            except Exception:
                pass
            return True
    except Exception as e:
        print(f"⚠️ 자동전화 발신 오류: {e}")
    return False

def _memory_autocall_loop():
    """능동형 자동전화 감시 루프 (별도 스레드). 기본 OFF."""
    if not MEMORY_AUTOCALL_ENABLED:
        print("🧠 기억의 앵커 자동전화: 비활성 (반응형 모드). ai_config.py MEMORY_AUTOCALL_ENABLED=True 로 켤 수 있음")
        return
    interval = max(5, MEMORY_AUTOCALL_CHECK_INTERVAL_MIN) * 60
    print(f"🧠 기억의 앵커 자동전화: 활성 (모드={MEMORY_AUTOCALL_MODE}, {MEMORY_AUTOCALL_CHECK_INTERVAL_MIN}분 주기)")
    # 부팅 직후 잠시 대기(다른 초기화 완료 후)
    time.sleep(60)
    while True:
        try:
            if not _autocall_within_hours():
                time.sleep(interval); continue
            state = _autocall_load_state()
            if not _autocall_daily_ok(state):
                time.sleep(interval); continue
            cand = _autocall_find_candidate()
            if cand and _autocall_cooldown_ok(state, cand["phone"]):
                did = False
                if MEMORY_AUTOCALL_MODE == "auto":
                    did = _autocall_place(cand)
                else:  # suggest
                    _autocall_notify_admin(cand)
                    did = True
                if did:
                    now_str = datetime.now().strftime("%Y-%m-%d %H:%M")
                    state.setdefault("last_called", {})[cand["phone"]] = now_str
                    state["daily"]["count"] = state.get("daily", {}).get("count", 0) + 1
                    _autocall_save_state(state)
        except Exception as e:
            print(f"⚠️ 자동전화 루프 오류(무시): {e}")
        time.sleep(interval)

# ── 보안 체크 함수 ──────────────────────────────
def is_admin(caller):
    return caller in ADMIN_NUMBERS

def is_blocked(caller):
    return caller in BLOCKED_NUMBERS

def is_pin_locked(caller):
    data = _load_pin_data()
    entry = data.get(caller, {})
    locked_until = entry.get("locked_until", 0)
    if locked_until <= 0:
        return False
    now = time.time()
    if now > locked_until:
        entry["count"] = 0
        entry["locked_until"] = 0
        data[caller] = entry
        _save_pin_data(data)
        return False
    remaining = int(locked_until - now)
    print(f"🔒 PIN 잠금 유지: {caller} (해제까지 {remaining}초)")
    return True

# ── 관리자 명령 PIN 인증 (통화별 1회) ────────────────
# 관리자가 '민감 명령'(연락처 저장·전화 걸기·SMS·예약)을 실행하려 할 때만 PIN을 확인한다.
# 한 통화(call_sid) 안에서 한 번 인증하면 통화 내내 유효하다.
# 일반 대화·오늘 일정 조회 등 읽기성 요청은 PIN 없이 그대로 동작한다.
ADMIN_PIN_REQUIRED = globals().get("ADMIN_PIN_REQUIRED", True)  # ai_config에서 끄고 켤 수 있음
_pin_verified_calls = set()   # PIN 인증 완료된 call_sid
_pin_pending = {}             # call_sid → 보류된 원래 명령(speech) (PIN 입력 후 재실행용)

# 민감 명령으로 판단할 키워드 (이 중 하나라도 있으면 PIN 필요)
_SENSITIVE_CMD_KEYWORDS = globals().get("SENSITIVE_CMD_KEYWORDS", [
    # 전화 걸기
    "전화해줘", "전화 해줘", "전화걸어줘", "전화 걸어줘", "연락해줘", "안부전화", "안부 전화",
    # 문자/SMS
    "문자", "메시지", "메세지", "sms", "SMS",
    # 연락처 저장
    "저장해줘", "저장해", "등록해줘", "등록해", "추가해줘", "추가해", "메모해줘", "기억해줘",
    # 예약
    "예약해줘", "예약해", "예약", "스케줄 잡아", "일정 잡아",
])

def _is_sensitive_command(speech):
    """이 발화가 PIN이 필요한 민감 명령인지 판단.
    '오늘 일정' 같은 읽기 전용 조회는 민감 명령이 아니다(전화/문자/저장/예약만 대상)."""
    if not speech:
        return False
    # 문자/SMS 는 '보내/전송'이 함께 있을 때만 민감(단순히 '메시지'라는 단어만으로는 제외)
    s = speech
    has_send = ("보내" in s) or ("전송" in s)
    for kw in _SENSITIVE_CMD_KEYWORDS:
        if kw in s:
            if kw in ("문자", "메시지", "메세지", "sms", "SMS") and not has_send:
                continue
            return True
    return False

def is_pin_verified(call_sid):
    return (not ADMIN_PIN_REQUIRED) or (call_sid in _pin_verified_calls)

def mark_pin_verified(call_sid):
    if call_sid:
        _pin_verified_calls.add(call_sid)

def clear_pin_state(call_sid):
    _pin_verified_calls.discard(call_sid)
    _pin_pending.pop(call_sid, None)

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
    def get_tts_voice(lang): return "Polly.Seoyeon-Neural"
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
    def get_tts_voice(lang): return "Polly.Seoyeon-Neural"
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

# ── 대화 히스토리 (통화 세션별 맥락 유지) ─────────────
_call_history = {}  # call_sid → [{"role": "user"/"assistant", "content": "..."}]

# ── 끼어들기(barge-in) 추적 ─────────────────────────────
# 설정값은 ai_config.py 에서 조절 (없으면 아래 기본값 사용)
# 전화 통화 답변 최대 토큰 수 (짧을수록 생성·낭독이 빨라짐). ai_config.py 에서 조절.
AI_MAX_TOKENS_CALL  = int(globals().get("AI_MAX_TOKENS_CALL", 100))

# 전화 봇 AI 모델. ai_config.py 의 CALL_MODEL 로 조절 (비어있으면 .env의 MODEL 유지).
# 예: "llama-3.3-70b-versatile"(빠름), "openai/gpt-oss-120b"(한글 정확)
_cfg_model = str(globals().get("CALL_MODEL", "")).strip()
if _cfg_model:
    MODEL = _cfg_model
    print(f"🧠 전화 봇 모델: {MODEL} (ai_config.py CALL_MODEL)")

# ── 💰 요금 폭탄 방지 설정 (ai_config.py 에서 조절) ──────
CALL_TIME_LIMIT_SEC        = int(globals().get("CALL_TIME_LIMIT_SEC", 240))
ALLOWED_COUNTRY_CODES      = globals().get("ALLOWED_COUNTRY_CODES",
                                ["+82", "+1", "+81", "+86", "+44", "+49", "+33", "+61"])
MAX_OUTBOUND_CALLS_PER_DAY = int(globals().get("MAX_OUTBOUND_CALLS_PER_DAY", 30))
MAX_SMS_PER_DAY            = int(globals().get("MAX_SMS_PER_DAY", 50))

# 하루 발신 카운터 (자정에 자동 초기화)
_daily_counters = {"date": None, "calls": 0, "sms": 0}

def _today_str():
    import datetime as _d
    return _d.date.today().isoformat()

def _reset_counters_if_new_day():
    today = _today_str()
    if _daily_counters["date"] != today:
        _daily_counters["date"] = today
        _daily_counters["calls"] = 0
        _daily_counters["sms"] = 0

def is_country_allowed(number):
    """발신 대상 번호가 허용 국가 코드로 시작하는지 검사 (프리미엄 번호 요금폭탄 방지)."""
    if not number:
        return False
    return any(str(number).startswith(cc) for cc in ALLOWED_COUNTRY_CODES)

def can_make_call():
    """하루 통화 한도 확인. (가능여부, 사유) 반환."""
    _reset_counters_if_new_day()
    if MAX_OUTBOUND_CALLS_PER_DAY > 0 and _daily_counters["calls"] >= MAX_OUTBOUND_CALLS_PER_DAY:
        return False, f"하루 통화 한도({MAX_OUTBOUND_CALLS_PER_DAY}건) 초과"
    return True, ""

def can_send_sms():
    """하루 문자 한도 확인. (가능여부, 사유) 반환."""
    _reset_counters_if_new_day()
    if MAX_SMS_PER_DAY > 0 and _daily_counters["sms"] >= MAX_SMS_PER_DAY:
        return False, f"하루 문자 한도({MAX_SMS_PER_DAY}건) 초과"
    return True, ""

def _record_call():
    _reset_counters_if_new_day()
    _daily_counters["calls"] += 1

def _record_sms():
    _reset_counters_if_new_day()
    _daily_counters["sms"] += 1

# ── 📞 관리자 수신전화 월 통화시간 제한 ───────────────────
MONTHLY_INBOUND_CALL_LIMIT_MIN = int(globals().get("MONTHLY_INBOUND_CALL_LIMIT_MIN", 300))
MONTHLY_CALL_WARN_PERCENT      = int(globals().get("MONTHLY_CALL_WARN_PERCENT", 90))
MONTHLY_CALL_LIMIT_ENABLED     = bool(globals().get("MONTHLY_CALL_LIMIT_ENABLED", True))
_MONTHLY_CALL_FILE = "/app/data/monthly_call_usage.json"

def _current_month_str():
    """월 통화시간 정산 주기 식별자. 매달 21일에 초기화되도록,
    21일부터 다음 달 20일까지를 한 주기로 본다.
    (예: 7/21~8/20 → '2026-07' 주기, 8/21~9/20 → '2026-08' 주기)
    반환값은 그 주기의 시작 달(YYYY-MM)."""
    import datetime as _d
    today = _d.date.today()
    if today.day >= 21:
        # 21일 이후 → 이번 달 21일에 시작한 주기
        return today.strftime("%Y-%m")
    else:
        # 20일 이하 → 지난 달 21일에 시작한 주기에 속함
        first = today.replace(day=1)
        prev = first - _d.timedelta(days=1)  # 지난 달 말일
        return prev.strftime("%Y-%m")

def _load_monthly_usage():
    """월 통화시간 사용량을 파일에서 로드. 달이 바뀌면 자동 초기화."""
    import json as _j, os as _os
    month = _current_month_str()
    data = {"month": month, "seconds": 0, "warned": False}
    try:
        if _os.path.exists(_MONTHLY_CALL_FILE):
            with open(_MONTHLY_CALL_FILE, "r") as f:
                saved = _j.load(f)
            if saved.get("month") == month:
                data = saved
            else:
                # 주기가 바뀜 → 초기화 (매달 21일 자동 리셋)
                print(f"🗓️ 정산 주기(매월 21일)가 바뀌어 통화시간 초기화: {saved.get('month')} → {month}")
    except Exception as e:
        print(f"⚠️ 월 통화시간 로드 오류(무시): {e}")
    return data

def _save_monthly_usage(data):
    import json as _j, os as _os
    try:
        _os.makedirs(_os.path.dirname(_MONTHLY_CALL_FILE), exist_ok=True)
        with open(_MONTHLY_CALL_FILE, "w") as f:
            _j.dump(data, f)
    except Exception as e:
        print(f"⚠️ 월 통화시간 저장 오류(무시): {e}")

def can_receive_admin_call():
    """관리자 수신전화 월 시간 한도 확인. (가능여부, 사유) 반환."""
    if not MONTHLY_CALL_LIMIT_ENABLED or MONTHLY_INBOUND_CALL_LIMIT_MIN <= 0:
        return True, ""
    usage = _load_monthly_usage()
    used_min = usage.get("seconds", 0) / 60.0
    if used_min >= MONTHLY_INBOUND_CALL_LIMIT_MIN:
        return False, f"이번 달 통화 한도({MONTHLY_INBOUND_CALL_LIMIT_MIN}분)를 모두 사용했습니다"
    return True, ""

def _record_inbound_call_seconds(seconds):
    """수신전화 통화시간(초)을 월 누적에 더하고, 90%/100% 도달 시 텔레그램 경고."""
    if not MONTHLY_CALL_LIMIT_ENABLED or MONTHLY_INBOUND_CALL_LIMIT_MIN <= 0:
        return
    try:
        seconds = int(float(seconds or 0))
    except (TypeError, ValueError):
        seconds = 0
    if seconds <= 0:
        return
    usage = _load_monthly_usage()
    usage["seconds"] = usage.get("seconds", 0) + seconds
    used_min   = usage["seconds"] / 60.0
    limit_min  = MONTHLY_INBOUND_CALL_LIMIT_MIN
    pct        = (used_min / limit_min * 100.0) if limit_min > 0 else 0

    print(f"📞 이번 달 수신전화 누적: {used_min:.1f}분 / {limit_min}분 ({pct:.0f}%)")

    # 90%(설정값) 이상 → 텔레그램 경고 1회
    if (MONTHLY_CALL_WARN_PERCENT > 0 and pct >= MONTHLY_CALL_WARN_PERCENT
            and not usage.get("warned", False) and pct < 100):
        usage["warned"] = True
        _notify_admin_telegram(
            f"⚠️ 통화 사용량 경고\n\n"
            f"이번 달 전화 사용 시간이 {pct:.0f}%에 도달했습니다.\n"
            f"({used_min:.0f}분 / {limit_min}분)\n\n"
            f"한도(100%)에 도달하면 다음 21일까지 전화 사용이 제한됩니다."
        )

    # 100% 도달 → 텔레그램 알림 (차단은 다음 통화 진입 시)
    if pct >= 100 and not usage.get("blocked_notified", False):
        usage["blocked_notified"] = True
        _notify_admin_telegram(
            f"🚫 통화 한도 초과\n\n"
            f"이번 달 전화 사용 시간({limit_min}분)을 모두 사용했습니다.\n"
            f"다음 21일까지 전화 사용이 제한됩니다.\n"
            f"(현재 {used_min:.0f}분 사용)"
        )
    _save_monthly_usage(usage)

def _notify_admin_telegram(message):
    """관리자에게 텔레그램 알림 전송 (기존 send_to_telegram 재사용). 실패해도 무시."""
    try:
        # 1순위: 기존 텔레그램 함수 재사용 (TELEGRAM_BOT_TOKEN/CHAT_ID 설정 시)
        if 'send_to_telegram' in globals() and send_to_telegram(message):
            print(f"📨 텔레그램 알림 전송: {message[:30]}...")
            return
        # 폴백: SMS 로 관리자에게
        if 'sms_client' in globals() and sms_client and MY_PHONE and TWILIO_PHONE:
            sms_client.messages.create(to=MY_PHONE, from_=TWILIO_PHONE, body=message)
            print(f"📨 (폴백)SMS 알림 전송")
    except Exception as e:
        print(f"⚠️ 관리자 알림 전송 실패(무시): {e}")

BARGEIN_THRESHOLD   = globals().get("BARGEIN_THRESHOLD", 0.6)
BARGEIN_MIN_SECONDS = globals().get("BARGEIN_MIN_SECONDS", 3.0)
BARGEIN_ENABLED     = globals().get("BARGEIN_ENABLED", True)
BARGEIN_NOTE        = globals().get("BARGEIN_NOTE",
    "[상황: 사용자가 당신의 이전 답변 도중에 끼어들어 새로 말했습니다. "
    "이전 답변을 계속 이어가지 말고, 먼저 '네', '아 그러셨군요' 같은 짧은 맞장구로 "
    "받아준 뒤, 아래 사용자의 새 말에 정확히 집중해서 답하세요.]")
OPERATOR_HINT_ENABLED = globals().get("OPERATOR_HINT_ENABLED", True)
OPERATOR_TRANSFER_ENABLED = globals().get("OPERATOR_TRANSFER_ENABLED", True)
OPERATOR_VOICE_ENABLED = globals().get("OPERATOR_VOICE_ENABLED", True)
OPERATOR_VOICE_KEYWORDS = globals().get("OPERATOR_VOICE_KEYWORDS", [
    "담당자", "사람이랑", "직접 연결", "관리자 바꿔", "사람 바꿔",
    "transfer", "connect me", "real person", "manager",
    "担当者", "人に繋いで", "转接", "找人"])

# 🧠 기억의 앵커 — 능동형 자동전화 설정 로드 (ai_config.py 에서 조절)
MEMORY_AUTOCALL_ENABLED   = globals().get("MEMORY_AUTOCALL_ENABLED", False)
MEMORY_AUTOCALL_MODE      = globals().get("MEMORY_AUTOCALL_MODE", "suggest")
MEMORY_AUTOCALL_HOURS     = globals().get("MEMORY_AUTOCALL_HOURS", [10, 20])
MEMORY_AUTOCALL_COOLDOWN_DAYS = globals().get("MEMORY_AUTOCALL_COOLDOWN_DAYS", 7)
MEMORY_AUTOCALL_MATCH     = globals().get("MEMORY_AUTOCALL_MATCH", ["time_slot", "weather"])
MEMORY_AUTOCALL_CHECK_INTERVAL_MIN = globals().get("MEMORY_AUTOCALL_CHECK_INTERVAL_MIN", 30)
MEMORY_AUTOCALL_MAX_PER_DAY = globals().get("MEMORY_AUTOCALL_MAX_PER_DAY", 3)
MEMORY_AUTOCALL_MISSION   = globals().get("MEMORY_AUTOCALL_MISSION",
    "예전 대화를 떠올리며 자연스럽게 안부를 묻고 근황을 확인")

# 언어별 TTS 실측 낭독 속도(초당 글자수). Twilio Neural TTS 기준 근사치.
BARGEIN_CPS = globals().get("BARGEIN_CPS", {"ko": 4.5, "en": 14.0, "ja": 5.5, "zh": 4.0})
# 끼어들기로 인정할 음성인식 신뢰도 상한 (이 값 이하이면 말이 겹친 정황으로 간주해 가점).
BARGEIN_CONF_HINT = globals().get("BARGEIN_CONF_HINT", 0.55)

_ai_speak_state = {}  # call_sid → {"start": epoch초, "reply": "직전 답변", "spoken_est": 예상낭독초, "lang": 언어}

def _estimate_speech_seconds(text, lang="ko"):
    """음성 합성(TTS) 낭독 예상 시간(초).
    언어별 실측 속도(BARGEIN_CPS)를 쓰고, 문장부호마다 짧은 정지 시간을 더해
    실제 낭독 길이에 가깝게 추정한다."""
    if not text:
        return 0.0
    cps = BARGEIN_CPS.get(lang, BARGEIN_CPS.get("ko", 4.5))
    base = len(text) / cps
    pauses = sum(text.count(p) for p in [",", ".", "?", "!", "，", "。", "？", "！", "、"])
    return max(1.0, base + pauses * 0.25)

def mark_ai_speaking(call_sid, reply, lang="ko"):
    """AI가 답변 낭독을 시작했음을 기록 (끼어들기 판단 기준)."""
    import time as _t
    if not call_sid:
        return
    _ai_speak_state[call_sid] = {
        "start": _t.time(),
        "reply": reply or "",
        "spoken_est": _estimate_speech_seconds(reply, lang),
        "lang": lang,
    }

def detect_barge_in(call_sid, confidence=None):
    """직전 AI 답변이 낭독을 마치기 전에 사용자가 말했는지(끼어들기) 판단.
    판단 근거: (1) 실측 경과시간 vs 실측 기반 예상 낭독시간,
    (2) Twilio Confidence(음성인식 신뢰도)가 낮으면 말이 겹친 정황(보조 가점).
    임계값은 ai_config.py 의 BARGEIN_THRESHOLD / BARGEIN_MIN_SECONDS 로 조절.
    끼어들기 횟수 제한은 없다."""
    import time as _t
    if not BARGEIN_ENABLED:
        _ai_speak_state.pop(call_sid, None)
        return False
    if not call_sid or call_sid not in _ai_speak_state:
        return False

    st = _ai_speak_state.pop(call_sid)
    spoken_est = st["spoken_est"]
    elapsed = _t.time() - st["start"]

    if spoken_est < BARGEIN_MIN_SECONDS:
        return False

    time_bargein = elapsed < (spoken_est * BARGEIN_THRESHOLD)

    conf_bargein = False
    if confidence is not None:
        try:
            c = float(confidence)
            if c <= BARGEIN_CONF_HINT and elapsed < (spoken_est * 0.85):
                conf_bargein = True
        except (TypeError, ValueError):
            pass

    is_bargein = time_bargein or conf_bargein
    if is_bargein:
        _reason = "시간" if time_bargein else "신뢰도"
        print(f"✋ 끼어들기 인정 (근거:{_reason}, 경과 {elapsed:.1f}s / 예상 {spoken_est:.1f}s): {call_sid}")
    return is_bargein

_MAX_HISTORY = 10   # 최대 10턴 유지 (메모리 절약)

# ── 수신전화 세션 추적 (보고용) ─────────────────────
inbound_sessions = {}   # call_sid → {"caller", "start", "history":[], "_timer": None}
_inbound_report_delay = 60  # 마지막 대화 후 60초 무응답이면 통화 종료로 판단

def get_call_history(call_sid):
    return _call_history.get(call_sid, [])

def add_call_history(call_sid, role, content):
    if call_sid not in _call_history:
        _call_history[call_sid] = []
    _call_history[call_sid].append({"role": role, "content": content})
    # 최대 턴 수 초과 시 오래된 것 제거
    if len(_call_history[call_sid]) > _MAX_HISTORY * 2:
        _call_history[call_sid] = _call_history[call_sid][-_MAX_HISTORY * 2:]

def clear_call_history(call_sid):
    _call_history.pop(call_sid, None)
    _ai_speak_state.pop(call_sid, None)
    clear_pin_state(call_sid)
    # 🤫 실시간 귓속말: 통화 종료 시 진행 목록/대기 지시 정리
    try:
        unregister_active_call(call_sid)
    except Exception:
        pass

def mark_history_interrupted(call_sid):
    """끼어들기 발생 시: 히스토리의 마지막 assistant 답변에 '중간에 끊김' 표시를 단다."""
    if not call_sid or call_sid not in _call_history:
        return
    hist = _call_history[call_sid]
    for i in range(len(hist) - 1, -1, -1):
        if hist[i].get("role") == "assistant":
            content = hist[i].get("content", "")
            if "[상대방이 중간에 끼어들어" not in content:
                hist[i]["content"] = (
                    content + " [상대방이 중간에 끼어들어 이 답변은 끝까지 전달되지 못함]"
                )
            break

def ask_openwebui(user_input, system_prompt=None, call_sid=None, max_tokens=None):
    """OpenWebUI API 호출 — 타임아웃 시 Groq 자동 폴백"""
    try:
        if not system_prompt:
            system_prompt = DEFAULT_SYSTEM_PROMPT

        # 대화 히스토리 구성
        history = get_call_history(call_sid) if call_sid else []
        messages = [{"role": "system", "content": system_prompt}]
        messages.extend(history)
        messages.append({"role": "user", "content": user_input})

        res = requests.post(
            f"{OPENWEBUI_URL}/api/chat/completions",
            headers={"Authorization": f"Bearer {OPENWEBUI_API_KEY}"},
            json={"model": MODEL, "messages": messages, "stream": False, "max_tokens": (max_tokens or AI_MAX_TOKENS_CALL), "temperature": 0.1},
            timeout=20  # 20초 제한 (기존 25초 → 단축)
        )
        reply = res.json()["choices"][0]["message"]["content"]

        # 히스토리 저장
        if call_sid:
            add_call_history(call_sid, "user", user_input)
            add_call_history(call_sid, "assistant", reply)

        return reply

    except requests.exceptions.Timeout:
        print(f"⚠️ OpenWebUI 타임아웃 → Groq 폴백")
        return None  # 폴백 신호
    except Exception as e:
        print(f"⚠️ OpenWebUI 오류 → Groq 폴백: {e}")
        return None  # 폴백 신호

def ask_groq(user_input, system_prompt=None, call_sid=None, max_tokens=None):
    """Groq API 호출 — 3회 재시도"""
    if not system_prompt:
        system_prompt = DEFAULT_SYSTEM_PROMPT
    import time as _time

    # 대화 히스토리 구성
    history = get_call_history(call_sid) if call_sid else []
    messages = [{"role": "system", "content": system_prompt}]
    messages.extend(history)
    messages.append({"role": "user", "content": user_input})

    for attempt in range(3):
        try:
            res = requests.post(
                GROQ_API_URL,
                headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
                json={"model": MODEL, "messages": messages, "max_tokens": (max_tokens or AI_MAX_TOKENS_CALL), "temperature": 0.1},
                timeout=15
            )
            data = res.json()
            if "choices" in data:
                reply = data["choices"][0]["message"]["content"]
                # 히스토리 저장
                if call_sid:
                    add_call_history(call_sid, "user", user_input)
                    add_call_history(call_sid, "assistant", reply)
                return reply
            err_msg = data.get("error", {}).get("message", "")
            print(f"Groq 재시도 ({attempt+1}/3): {err_msg}")
            _time.sleep(2)
        except Exception as e:
            print(f"Groq 오류: {e}")
            _time.sleep(2)
    return "죄송합니다. 잠시 후 다시 말씀해주세요."

def get_ai_reply(user_input, system_prompt=None, call_sid=None, max_tokens=None):
    """AI 응답 라우팅
    BOT_MODE=1: OpenWebUI (실패 시 Groq 자동 폴백)
    BOT_MODE=2: Groq 직결 (기본값, 빠름) — Groq Key 없으면 OpenWebUI 자동 전환
    BOT_MODE=3: 포워딩 (AI 없음)
    max_tokens: 응답 최대 토큰. None이면 통화용 기본값(AI_MAX_TOKENS_CALL).
                보고 요약처럼 긴 답이 필요할 땐 크게 지정.
    """
    if BOT_MODE == "2":
        # Groq Key 없으면 OpenWebUI로 자동 전환
        if not GROQ_API_KEY:
            print("⚠️ Groq API Key 없음 → OpenWebUI 자동 전환")
            result = ask_openwebui(user_input, system_prompt, call_sid, max_tokens=max_tokens)
            return result if result else "죄송합니다. AI 서버에 연결할 수 없습니다."
        return ask_groq(user_input, system_prompt, call_sid, max_tokens=max_tokens)

    # BOT_MODE=1: OpenWebUI 시도
    result = ask_openwebui(user_input, system_prompt, call_sid, max_tokens=max_tokens)
    if result is None:
        # 타임아웃/오류 → Groq 폴백
        if GROQ_API_KEY:
            print("🔄 Groq 폴백 실행")
            return ask_groq(user_input, system_prompt, call_sid, max_tokens=max_tokens)
        return "죄송합니다. AI 서버에 연결할 수 없습니다."
    return result

# ── RAG 검색 (openapi-tools 컨테이너에 HTTP 요청) ──────
TOOLS_API_URL = os.getenv("TOOLS_API_URL", "http://openapi-tools:8000")

def rag_lookup(query, top_k=2):
    """전화 통화 중 상대방 질문에 대해 RAG 검색 — openapi-tools의 /rag/search 호출"""
    try:
        # 🆕 개인용(personal) 모드면 통합 검색을 요청한다. (.env 를 안 고쳐도
        #    ai_config.py 의 SERVICE_MODE 만으로 검색 범위가 바뀌도록 연동)
        #    고객용(customer)이면 unified 를 보내지 않아 tools-api 의 .env 기본값을 따른다.
        _svc = str(globals().get("SERVICE_MODE", "customer")).strip().lower()
        _payload = {"query": query, "top_k": top_k}
        if _svc == "personal":
            _payload["unified"] = True
        r = requests.post(
            f"{TOOLS_API_URL}/rag/search",
            json=_payload,
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
        if not TWILIO_AUTH_TOKEN:
            print("🚫 TWILIO_AUTH_TOKEN 미설정 — 보안을 위해 모든 Webhook 요청 차단")
            return Response("Forbidden — Auth Token not configured", status=403)
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
            print(f"🚨 서명 검증 오류 → 차단: {e}")
            return Response("Forbidden", status=403)
        return f(*args, **kwargs)
    return decorated

# ── API 인증 ──────────────────────────────────
API_SECRET = os.getenv("API_SECRET", "")

def require_api_secret(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not API_SECRET:
            # 🔒 방어심층화: API_SECRET 미설정 시 통과(fail-open)가 아니라 차단(fail-closed).
            #    설치 스크립트가 항상 생성하므로 정상 환경에선 발생하지 않지만,
            #    설정 누락 시 무인증 노출을 막는다.
            print("🚫 API_SECRET 미설정 — 보안을 위해 관리 API 요청 차단")
            return Response("Service Unavailable — API secret not configured", status=503)
        token = request.headers.get("X-API-Secret", "")  # URL 쿼리 허용 안함 (로그 노출 방지)
        if not hmac.compare_digest(token, API_SECRET):
            print(f"🚨 API 인증 실패: {request.remote_addr}")
            return Response("Unauthorized", status=401)
        return f(*args, **kwargs)
    return decorated

# ── 아웃바운드 세션 ────────────────────────────
outbound_sessions = {}
inbound_slow_down = {}  # 수신전화 천천히 요청 횟수 추적

# ── 보안: voice-report 메시지 내부 저장소 (TTS 인젝션 방지) ──
_pending_reports = {}

def store_report_message(msg):
    """보고 메시지를 내부에 저장하고 ID 반환 (URL 노출 방지)"""
    import secrets as _secrets
    report_id = _secrets.token_urlsafe(16)
    _pending_reports[report_id] = {"msg": msg[:600], "created": time.time()}
    now = time.time()
    expired = [k for k, v in _pending_reports.items() if now - v["created"] > 3600]
    for k in expired:
        del _pending_reports[k]
    return report_id

# ── 메모리 자동 정리 (30분 주기) ────────────────
_SESSION_TTL_SECONDS = 1800  # 30분 이상 된 세션 자동 삭제
_CLEANUP_INTERVAL = 600      # 10분마다 정리 실행

def _cleanup_stale_sessions():
    """메모리 누수 방지: 오래된 세션/히스토리 자동 정리"""
    now = time.time()
    # 1. outbound_sessions: summary_sent=True이거나 30분 경과 시 삭제
    stale_sids = []
    for sid, sess in outbound_sessions.items():
        start = sess.get("call_start_time") or now
        age = now - start
        if sess.get("summary_sent", False) or age > _SESSION_TTL_SECONDS:
            stale_sids.append(sid)
    for sid in stale_sids:
        del outbound_sessions[sid]
    # 2. _call_history: 대응하는 세션이 없으면 삭제
    stale_hist = [sid for sid in _call_history if sid not in outbound_sessions]
    for sid in stale_hist:
        del _call_history[sid]
    # 3. inbound_sessions: report_sent=True이거나 30분 경과 시 삭제
    stale_inbound = []
    for sid, sess in inbound_sessions.items():
        if sess.get("report_sent", False):
            stale_inbound.append(sid)
        else:
            try:
                start_str = sess.get("start", "")
                if start_str:
                    start_time = datetime.strptime(start_str, "%Y-%m-%d %H:%M:%S")
                    if (datetime.now() - start_time).total_seconds() > _SESSION_TTL_SECONDS:
                        stale_inbound.append(sid)
            except Exception:
                stale_inbound.append(sid)
    for sid in stale_inbound:
        timer = inbound_sessions[sid].get("_timer")
        if timer:
            timer.cancel()
        del inbound_sessions[sid]
    # 4. inbound_slow_down: 전체 초기화 (수신전화 카운터)
    inbound_slow_down.clear()
    # 로그
    total_cleaned = len(stale_sids) + len(stale_hist) + len(stale_inbound)
    if total_cleaned > 0:
        print(f"🧹 메모리 정리: 발신 {len(stale_sids)}개 + 수신 {len(stale_inbound)}개 + 히스토리 {len(stale_hist)}개 삭제 | 잔여: 발신 {len(outbound_sessions)}개 수신 {len(inbound_sessions)}개")
    # 다음 정리 예약
    threading.Timer(_CLEANUP_INTERVAL, _cleanup_stale_sessions).start()

# 서버 시작 시 자동 정리 타이머 가동
threading.Timer(_CLEANUP_INTERVAL, _cleanup_stale_sessions).start()

def make_call(to_number, custom_message=None, contact_name=None, mission=None, report_to=None):
    # 💰 요금 폭탄 방지: 허용 국가 코드 + 하루 통화 한도 검사
    if not is_country_allowed(to_number):
        print(f"🚨 통화 차단: 허용되지 않은 국가 코드 → {str(to_number)[:4]}*** (요금폭탄 방지)")
        return None
    _ok, _reason = can_make_call()
    if not _ok:
        print(f"🚨 통화 차단: {_reason} (요금폭탄 방지)")
        return None
    try:
        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

        # 녹음 설정 (ENABLE_CALL_RECORDING=true 시 자동 녹음)
        rec_kwargs = {}
        if ENABLE_CALL_RECORDING:
            rec_kwargs["record"] = True
            rec_kwargs["recording_status_callback"] = f"{SERVER_DOMAIN}/recording-callback"
            rec_kwargs["recording_status_callback_method"] = "POST"
            rec_kwargs["recording_status_callback_event"] = ["completed"]

        if contact_name and mission:
            call = client.calls.create(
                to=to_number, from_=TWILIO_PHONE,
                url=f"{SERVER_DOMAIN}/voice-out-welfare",
                status_callback=f"{SERVER_DOMAIN}/call-status",
                status_callback_method="POST",
                status_callback_event=["initiated", "ringing", "answered", "completed", "no-answer", "failed", "busy", "canceled"],
                time_limit=CALL_TIME_LIMIT_SEC,  # ai_config의 CALL_TIME_LIMIT_SEC (요금폭탄 방지)
                **rec_kwargs
            )
            outbound_sessions[call.sid] = {
                "name"        : contact_name,
                "number"      : to_number,
                "mission"     : mission,
                "greeting"    : custom_message or f"{contact_name}님, " + MSG_GREETING_DEFAULT,
                "history"     : [],
                "summary_sent": False,
                "report_to"   : report_to or MY_PHONE,
                "call_start_time": None,  # voice_out_welfare에서 실제 통화 시작 시 기록
            }
            print(f"📞 안부전화 세션 생성: {call.sid} → {contact_name}({to_number}) | 보고→{report_to or MY_PHONE}")
        else:
            call = client.calls.create(
                to=to_number, from_=TWILIO_PHONE,
                url=f"{SERVER_DOMAIN}/voice-out-simple",
                time_limit=CALL_TIME_LIMIT_SEC  # 요금폭탄 방지 (시간 제한)
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
        _record_call()  # 하루 통화 카운터 증가 (요금폭탄 방지)
        return call.sid
    except Exception as e:
        print(f"전화 걸기 오류: {e}")
        return None

def send_summary_to_admin(call_sid):
    """통화 종료 후 지정된 번호에 전화+SMS로 요약 보고"""
    session = outbound_sessions.get(call_sid)
    if not session or session.get("summary_sent", False):
        return
    session["summary_sent"] = True

    report_to = session.get("report_to", MY_PHONE)

    # ── 실제 대화 여부 판단 ──
    history_entries = [h for h in session["history"] if h.get("user") and h["user"].strip()]
    connected = len(history_entries) > 0

    history_text = "\n".join([
        f"AI: {h['ai']}\n상대: {h['user']}"
        for h in history_entries
    ]) if connected else "대화 내용 없음 (상대방이 전화를 받지 않았거나 자동응답으로 연결됨)"

    force_hangup = session.get("force_hangup", False)
    time_limit_ended = session.get("time_limit_ended", False)

    if connected and not force_hangup and not time_limit_ended:
        # 정상 종료 — 전체 대화 요약
        summary_prompt = f"""다음은 {session['name']}님과의 실제 통화 내용입니다.
임무: {session['mission']}
대화 내용:
{history_text}

⚠️ 주의: 상대방이 말을 더듬거나 음성인식이 불완전할 수 있습니다.
불완전한 문장도 문맥에서 의미를 최대한 유추하여 자연스럽게 요약하세요.

위 통화를 3~4문장으로 요약해주세요.
1. 상대방의 현재 상태/기분
2. 대화에서 파악된 핵심 내용
3. 임무({session['mission']}) 달성 여부
실제로 나눈 대화를 기반으로 요약하세요."""

    elif connected and time_limit_ended:
        # 통화 시간 초과 종료 (4분 제한) — 대화 맥락 보고
        turn_count = len(history_entries)
        summary_prompt = f"""다음은 {session['name']}님과의 통화 내용입니다.
임무: {session['mission']}
상황: 통화 시간 제한(4분)으로 인해 AI가 대화를 정리하고 종료했습니다. ({turn_count}턴 대화)
대화 내용:
{history_text}

⚠️ 주의: 상대방이 말을 더듬거나 음성인식이 불완전할 수 있습니다.
불완전한 문장도 문맥에서 의미를 최대한 유추하세요.

위 통화를 3~4문장으로 요약해주세요.
1. 상대방의 현재 상태/기분
2. 대화에서 파악된 핵심 내용
3. 임무({session['mission']}) 달성 여부 (시간 제한으로 종료되었으므로 미완료 가능성 언급)
4. 담당자가 추가로 확인해야 할 사항이 있다면 언급
실제로 나눈 대화를 기반으로 요약하되, 시간 제한으로 종료되어 담당자 직접 확인을 안내했다는 점을 포함하세요."""

    elif connected and force_hangup:
        # 강제 종료 — 대화 중 끊김 명시
        turn_count = len(history_entries)
        summary_prompt = f"""다음은 {session['name']}님과의 통화 내용입니다.
임무: {session['mission']}
상황: 상대방이 대화 도중 전화를 강제로 끊었습니다. ({turn_count}턴 대화 후 종료)
대화 내용:
{history_text}

⚠️ 주의: 상대방이 말을 더듬거나 음성인식이 불완전할 수 있습니다.
불완전한 문장도 문맥에서 의미를 최대한 유추하세요.

위 통화를 3~4문장으로 요약해주세요.
1. 상대방의 현재 상태/기분 (대화가 중간에 끊겼음을 명시)
2. 대화에서 파악된 핵심 내용 (끊기기 전까지)
3. 임무({session['mission']}) 달성 여부 (미완료 가능성 언급)
실제로 나눈 대화를 기반으로 요약하되, 대화가 중간에 끊겼다는 사실을 반드시 포함하세요."""

    else:
        # 연결 안 됨
        summary_prompt = f"""{session['name']}님과 통화를 시도했으나 연결되지 않았습니다.
임무: {session['mission']}
상황: 상대방이 전화를 받지 않았거나 자동응답(소리샘)으로 연결됐습니다.
이 상황을 2문장으로 간단히 보고하세요."""

    summary = get_ai_reply(summary_prompt,
        "당신은 통화 내용을 요약 보고하는 비서입니다. 한국어로 간결하게 보고하세요. "
        "실제 통화가 이루어진 경우 대화 내용을 정확히 요약하고, "
        "연결이 안 된 경우 그 사실만 간단히 보고하세요. "
        "'음성인식 오류' 같은 기술적 표현은 사용하지 마세요.", max_tokens=400)

    sms_prompt = f"""다음 요약을 SMS용으로 250자 이내로 압축하세요. 핵심 내용이 잘리지 않게 담되, 250자를 넘기지 마세요.
요약: {summary}
250자 이내 SMS:"""
    sms_summary = get_ai_reply(sms_prompt, "250자 이내로만 답하세요. 핵심을 빠뜨리지 말고 자연스럽게 요약하세요.", max_tokens=400)

    # 🧠 기억의 앵커: 대리전화 대화를 전화번호별로 임베딩 저장 (다음 통화 회상용)
    try:
        if connected:
            save_call_memory(
                phone_number=session.get("number", ""),
                name=session.get("name", ""),
                conversation_text=history_text,
                extra_summary=summary,
            )
    except Exception as _me:
        print(f"⚠️ 기억 저장 훅 오류(무시): {_me}")

    voice_report = f"{session['name']}님 통화 완료. {summary}"
    # 음성 보고 메시지 450자 제한 (내부 저장소 방식이라 URL 길이 문제 없음)
    if len(voice_report) > 450:
        voice_report = voice_report[:447] + "..."
    sms_report   = f"[AI통화보고] {session['name']}님: {sms_summary}"

    print(f"📋 통화 요약 (보고→{report_to}): {voice_report}")

    # Telegram 알림 메시지 준비 (SMS 보고 시점에 같이 발송)
    display_number = session.get('number', '')
    if display_number.startswith("+82"):
        display_number = "0" + display_number[3:]
    # 보고 대상 표시 (관리자 외 다른 번호로 보고 시 표시)
    report_display = report_to.replace("+82", "0") if report_to.startswith("+82") else report_to
    report_line = f"\n📩 보고대상: {report_display}" if report_to != MY_PHONE else ""
    tg_msg = f"📞 <b>[AI통화보고]</b>\n👤 대상: {session['name']}님 ({display_number})\n📋 임무: {session.get('mission','안부 확인')}\n📊 결과: {summary}{report_line}"
    if len(tg_msg) > 4000:
        tg_msg = tg_msg[:3997] + "..."

    client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

    # ── ① 전화 음성 보고 (TIMER_CALL_REPORT초 후 발신) ────────────────
    def send_call_delayed():
        try:
            report_id = store_report_message(voice_report)
            report_url = f"{SERVER_DOMAIN}/voice-report?rid={report_id}"
            client.calls.create(to=report_to, from_=TWILIO_PHONE, url=report_url)
            print(f"📞 음성 보고 전화 발신 ({TIMER_CALL_REPORT}초 지연) → {report_to}")
        except Exception as e:
            print(f"음성 보고 전화 오류: {e}")
            # 음성 보고 실패 시 SMS로 대체 보고
            try:
                client.messages.create(to=report_to, from_=TWILIO_PHONE, body=f"[음성보고 실패] {voice_report}")
                print(f"📱 음성보고 실패 → SMS 대체 발송")
            except Exception:
                pass
    
    threading.Timer(TIMER_CALL_REPORT, send_call_delayed).start()

    # ── ② SMS 문자 + Telegram 알림 (TIMER_SMS_REPORT초 후 발송) ──────────────────────
    def send_sms_delayed():
        try:
            client.messages.create(
                to=report_to,
                from_=TWILIO_PHONE,
                body=sms_report
            )
            print(f"📱 SMS 보고 발송 ({TIMER_SMS_REPORT}초 지연) → {report_to}")
        except Exception as e:
            print(f"SMS 보고 오류: {e}")
        # Telegram 알림 (SMS와 동시 발송)
        send_to_telegram(tg_msg)
    
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

    # ── PDF 보고서 자동 생성 (ENABLE_PDF_REPORT=true 시) ──
    if ENABLE_PDF_REPORT and call_sid in outbound_sessions:
        outbound_sessions[call_sid]["_pdf_summary"] = summary
        threading.Timer(3.0, generate_call_report_pdf, args=[call_sid]).start()

# ── 수신전화 보고 (SMS + Telegram + PDF) ──────────────
def send_inbound_report(call_sid):
    """수신전화 종료 후 관리자에게 SMS + Telegram + PDF 보고"""
    session = inbound_sessions.get(call_sid)
    if not session or session.get("report_sent", False):
        return
    session["report_sent"] = True

    caller = session.get("caller", "")
    history = session.get("history", [])

    if not history:
        # 대화 없이 끊김 — 보고 생략
        inbound_sessions.pop(call_sid, None)
        clear_call_history(call_sid)
        return

    # 발신자 표시
    display_number = caller.replace("+82", "0") if caller.startswith("+82") else caller
    caller_name = "알 수 없음"
    for name, num in CONTACTS.items():
        if num == caller:
            caller_name = name
            break

    # 대화 내용 텍스트
    history_text = "\n".join([
        f"발신자: {h['user']}\nAI: {h['ai']}"
        for h in history if h.get("user")
    ])

    # AI 요약 생성
    summary_prompt = f"""다음은 외부에서 걸려온 수신전화 대화 내용입니다.
발신자: {caller_name} ({display_number})
대화 내용:
{history_text}

위 통화를 3~4문장으로 요약해주세요.
1. 발신자가 어떤 용건으로 전화했는지
2. AI가 어떻게 응대했는지
3. 추가 조치가 필요한지
실제 대화 내용을 기반으로 요약하세요."""

    summary = get_ai_reply(summary_prompt,
        "당신은 수신전화 내용을 요약 보고하는 비서입니다. 한국어로 간결하게 보고하세요.", max_tokens=400)

    # 🧠 기억의 앵커: 수신전화 대화도 발신자 번호별로 임베딩 저장
    try:
        save_call_memory(
            phone_number=caller,
            name=caller_name if caller_name != "알 수 없음" else "",
            conversation_text=history_text,
            extra_summary=summary,
        )
    except Exception as _me:
        print(f"⚠️ 기억 저장 훅 오류(무시): {_me}")

    sms_prompt = f"다음 요약을 SMS용으로 250자 이내로 압축하세요. 핵심 내용이 잘리지 않게 담되, 250자를 넘기지 마세요.\n요약: {summary}\n250자 이내 SMS:"
    sms_summary = get_ai_reply(sms_prompt, "250자 이내로만 답하세요. 핵심을 빠뜨리지 말고 자연스럽게 요약하세요.", max_tokens=400)

    sms_report = f"[수신전화보고] {caller_name}({display_number}): {sms_summary}"
    tg_msg = f"📞 <b>[수신전화 보고]</b>\n👤 발신자: {caller_name} ({display_number})\n📊 내용: {summary}"
    if len(tg_msg) > 4000:
        tg_msg = tg_msg[:3997] + "..."

    print(f"📋 수신전화 요약 보고: {caller_name}({display_number})")

    # ① SMS 보고 (관리자에게)
    try:
        sms_client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        sms_client.messages.create(to=MY_PHONE, from_=TWILIO_PHONE, body=sms_report)
        print(f"📱 수신전화 SMS 보고 → {MY_PHONE}")
    except Exception as e:
        print(f"수신전화 SMS 보고 오류: {e}")

    # ② Telegram 알림
    send_to_telegram(tg_msg)

    # ③ PDF 보고서 (ENABLE_PDF_REPORT=true 시)
    if ENABLE_PDF_REPORT:
        try:
            from datetime import datetime as dt
            timestamp = dt.now().strftime("%Y%m%d_%H%M%S")
            safe_name = re.sub(r'[^\w가-힣]', '_', caller_name)
            filename = f"report_{timestamp}_{safe_name}_inbound.pdf"
            filepath = os.path.join(REPORTS_DIR, filename)

            from fpdf import FPDF
            pdf = FPDF()
            pdf.add_page()
            # 한글 폰트 감지
            font_paths = ["/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
                          "/usr/share/fonts/nanum-fonts/NanumGothic.ttf"]
            font_set = False
            for fp in font_paths:
                if os.path.exists(fp):
                    pdf.add_font("NanumGothic", "", fp, uni=True)
                    pdf.set_font("NanumGothic", size=11)
                    font_set = True
                    break
            if not font_set:
                try:
                    pdf.add_font("DejaVu", "", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", uni=True)
                    pdf.set_font("DejaVu", size=11)
                except:
                    pdf.set_font("Helvetica", size=11)

            pdf.set_font_size(16)
            pdf.cell(0, 12, "수신전화 통화 보고서", ln=True, align="C")
            pdf.set_font_size(9)
            pdf.cell(0, 8, f"생성: {dt.now().strftime('%Y-%m-%d %H:%M:%S')}", ln=True, align="C")
            pdf.ln(5)
            pdf.set_font_size(11)
            pdf.cell(0, 8, f"발신자: {caller_name} ({display_number})", ln=True)
            pdf.ln(3)
            pdf.cell(0, 8, "[ 대화 내용 ]", ln=True)
            pdf.set_font_size(10)
            for h in history:
                if h.get("user"):
                    pdf.multi_cell(0, 6, f"발신자: {h['user']}")
                if h.get("ai"):
                    pdf.multi_cell(0, 6, f"AI: {h['ai']}")
                pdf.ln(2)
            pdf.ln(3)
            pdf.set_font_size(11)
            pdf.cell(0, 8, "[ AI 요약 ]", ln=True)
            pdf.set_font_size(10)
            pdf.multi_cell(0, 6, summary)

            pdf.output(filepath)
            print(f"📄 수신전화 PDF 보고서 생성: {filename}")
            send_to_telegram(f"📄 <b>[수신전화 PDF 보고서]</b>\n👤 발신자: {caller_name}\n📁 파일: {filename}")
        except Exception as e:
            print(f"⚠️ 수신전화 PDF 보고서 생성 실패: {e}")

    # ④ 통화 기록 저장 (대시보드용)
    try:
        from call_history import save_record
        save_record({
            "call_sid": call_sid,
            "name": caller_name,
            "number": caller,
            "mission": "수신전화 응대",
            "history": history,
            "summary": summary,
            "sms_summary": sms_summary,
            "report_to": MY_PHONE,
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "status": "inbound_completed"
        })
    except Exception as e:
        print(f"⚠️ 수신전화 기록 저장 실패: {e}")

    # 세션 정리
    inbound_sessions.pop(call_sid, None)
    clear_call_history(call_sid)

# ── 명령 처리 ──────────────────────────────────
def _read_calendar_key():
    """공유 폴더에서 OpenWebUI API 키를 읽어 반환 (없으면 빈 문자열)."""
    for _p in ("/owui-data/shared-key/openwebui_api_key", "/shared-key/openwebui_api_key"):
        try:
            with open(_p, "r") as _f:
                k = _f.read().strip()
            if k:
                return k
        except Exception:
            continue
    return ""

def _cal_url():
    return os.getenv("OPENWEBUI_URL", "http://open-webui:8080").rstrip("/")

def _ns_from_epoch(sec):
    """epoch초 → 나노초(정수). OpenWebUI 캘린더는 start_at/end_at 를 ns 로 저장."""
    return int(sec) * 1_000_000_000

def _fmt_event_time(ns, all_day):
    """이벤트 시각(ns 등)을 '14시 30분' 형태로. all_day 면 '종일'."""
    import datetime as _dt
    if all_day:
        return "종일"
    if not ns:
        return ""
    try:
        ns = int(ns)
    except (TypeError, ValueError):
        return ""
    # 저장 단위가 ns/us/ms/s 중 무엇이든 초 단위로 환산
    if ns > 1_000_000_000_000_000_000:
        sec = ns / 1_000_000_000
    elif ns > 1_000_000_000_000_000:
        sec = ns / 1_000_000
    elif ns > 1_000_000_000_000:
        sec = ns / 1_000
    else:
        sec = ns
    return _dt.datetime.fromtimestamp(sec).strftime("%H시 %M분")

def _get_default_calendar_id(key):
    """사용자의 기본 캘린더 id 를 조회. 실패 시 None.
    (이벤트 생성에는 calendar_id 가 반드시 필요하다.)"""
    try:
        _s = requests.Session(); _s.trust_env = False
        r = _s.get(f"{_cal_url()}/api/v1/calendars/",
                   headers={"Authorization": f"Bearer {key}"},
                   timeout=30, allow_redirects=False)
        if r.status_code >= 400:
            return None
        cals = r.json()
    except Exception:
        return None
    if not isinstance(cals, list) or not cals:
        return None
    # 시스템(예약작업) 캘린더는 제외하고, 기본(is_default) 우선
    real = [c for c in cals if c.get("id") != "__scheduled_tasks__"]
    if not real:
        return None
    for c in real:
        if c.get("is_default"):
            return c.get("id")
    return real[0].get("id")

def _get_calendar_events_voice(target_date, label=None):
    """특정 날짜(target_date: datetime.date)의 일정을 음성용 텍스트로 반환.
    실패해도 원인 문자열을 반환한다 (가짜 일정 방지)."""
    import datetime as _dt
    key = _read_calendar_key()
    if not key:
        return ("캘린더 키가 설정되지 않았습니다. "
                "오픈웹유아이 채팅에서 캘린더 도구에 키를 입력하고 한 번 실행해 주세요.")
    start_iso = f"{target_date.isoformat()}T00:00:00"
    end_iso = f"{(target_date + _dt.timedelta(days=1)).isoformat()}T00:00:00"
    try:
        _s = requests.Session(); _s.trust_env = False
        r = _s.get(f"{_cal_url()}/api/v1/calendars/events",
                   headers={"Authorization": f"Bearer {key}"},
                   params={"start": start_iso, "end": end_iso},
                   timeout=30, allow_redirects=False)
    except Exception:
        return "캘린더 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요."
    if r.status_code in (401, 403):
        return "캘린더 키 인증에 실패했습니다. 키가 만료되었을 수 있으니 새 키로 다시 설정해 주세요."
    if r.status_code >= 400:
        return "일정을 가져오지 못했습니다. 잠시 후 다시 시도해 주세요."
    try:
        events = r.json()
    except Exception:
        return "일정 정보를 해석하지 못했습니다."

    day_label = label or f"{target_date.month}월 {target_date.day}일"
    if not events:
        return f"{day_label}에는 예정된 일정이 없습니다."

    def _k(e):
        try:
            return int(e.get("start_at") or 0)
        except (TypeError, ValueError):
            return 0
    events = sorted(events, key=_k)
    parts = [f"{day_label}의 일정입니다"]
    for e in events:
        when = _fmt_event_time(e.get("start_at"), e.get("all_day", False))
        title = e.get("title") or "제목 없음"
        loc = e.get("location")
        seg = f"{when} {title}" if when else title
        if loc:
            seg += f", 장소는 {loc}"
        parts.append(seg)
    return ". ".join(parts) + "."

def _calendar_event_exists(title, start_epoch, tolerance_sec=120):
    """캘린더에 (제목 + 시작시각)이 일치하는 일정이 아직 있는지 확인.
    삭제된 일정의 알림 전화를 막기 위해 알림 발송 직전에 호출한다.
    반환: True(존재)/False(없음/삭제됨). 조회 실패 시엔 안전하게 True(발송 유지)."""
    key = _read_calendar_key()
    if not key:
        return True
    try:
        target_ns = int(start_epoch) * 1_000_000_000
        tol_ns = int(tolerance_sec) * 1_000_000_000
        _s = requests.Session(); _s.trust_env = False
        r = _s.get(f"{_cal_url()}/api/v1/calendars/events",
                   headers={"Authorization": f"Bearer {key}"},
                   timeout=15, allow_redirects=False)
        if r.status_code >= 400:
            return True
        events = r.json()
        if isinstance(events, dict):
            events = events.get("events", events.get("data", []))
        if not isinstance(events, list):
            return True
        _title = (title or "").strip()
        for e in events:
            e_title = (e.get("title") or "").strip()
            try:
                e_start = int(e.get("start_at") or 0)
            except (TypeError, ValueError):
                e_start = 0
            if e_title == _title and abs(e_start - target_ns) <= tol_ns:
                return True
        return False
    except Exception:
        return True


def _create_calendar_event(title, start_epoch, end_epoch=None, all_day=False, location="", description="", reminder_min=None):
    """OpenWebUI 캘린더에 이벤트를 생성. (title, start_epoch=초) 필요.
    reminder_min: 알림(분 전). None 이면 캘린더 기본값(10분) 사용.
    성공/실패 사유를 담은 (bool, 메시지) 튜플 반환."""
    key = _read_calendar_key()
    if not key:
        return (False, "캘린더 키가 설정되지 않아 일정을 등록할 수 없습니다. "
                       "오픈웹유아이 채팅에서 캘린더 도구에 키를 먼저 입력해 주세요.")
    calendar_id = _get_default_calendar_id(key)
    if not calendar_id:
        return (False, "등록할 캘린더를 찾지 못했습니다. 오픈웹유아이에서 캘린더를 먼저 만들어 주세요.")
    payload = {
        "calendar_id": calendar_id,
        "title": title or "제목 없음",
        "start_at": _ns_from_epoch(start_epoch),
        "all_day": bool(all_day),
    }
    if end_epoch:
        payload["end_at"] = _ns_from_epoch(end_epoch)
    if location:
        payload["location"] = location
    if description:
        payload["description"] = description
    # 알림(reminder): OpenWebUI 는 이벤트 메타의 alert_minutes 로 저장한다.
    #   (docs: 개별 이벤트는 meta.alert_minutes 로 기본 10분 알림을 재정의)
    if reminder_min is not None:
        try:
            payload["meta"] = {"alert_minutes": int(reminder_min)}
        except (TypeError, ValueError):
            pass
    try:
        _s = requests.Session(); _s.trust_env = False
        r = _s.post(f"{_cal_url()}/api/v1/calendars/events/create",
                    headers={"Authorization": f"Bearer {key}",
                             "Content-Type": "application/json"},
                    json=payload, timeout=30, allow_redirects=False)
    except Exception:
        return (False, "캘린더 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.")
    if r.status_code in (401, 403):
        return (False, "캘린더 키 인증에 실패했습니다. 새 키로 다시 설정해 주세요.")
    if r.status_code >= 400:
        return (False, "일정 등록에 실패했습니다. 잠시 후 다시 시도해 주세요.")
    return (True, "")


def _schedule_event_reminder(title, start_epoch, reminder_min):
    """캘린더 일정의 알림 시각(일정시작 - reminder_min)에 맞춰
    관리자 본인에게 '전화 + SMS' 알림 예약을 scheduler 에 1회 등록한다.
    reminder_min 이 없으면 아무것도 하지 않는다.
    반환: 예약 성공 시 True, 아니면 False."""
    if not reminder_min:
        return False
    try:
        rem = int(reminder_min)
    except (TypeError, ValueError):
        return False
    if rem <= 0:
        return False
    if not MY_PHONE:
        print("⚠️ 일정 알림 예약 생략: 관리자 전화번호(MY_PHONE) 미설정")
        return False

    import datetime as _dt
    # 알림 시각 = 일정 시작 - reminder_min 분
    alert_epoch = int(start_epoch) - rem * 60
    now_epoch = int(_dt.datetime.now().timestamp())
    if alert_epoch <= now_epoch:
        # 이미 알림 시각이 지났으면(임박 일정) 예약하지 않음
        print(f"⚠️ 일정 알림 예약 생략: 알림 시각이 이미 지남 ('{title}')")
        return False

    alert_dt = _dt.datetime.fromtimestamp(alert_epoch)
    sched_time = alert_dt.strftime("%Y-%m-%d %H:%M")

    # 알림 문구 (전화 TTS / SMS 공용)
    if rem >= 1440 and rem % 1440 == 0:
        rem_txt = f"{rem // 1440}일 후"
    elif rem >= 60 and rem % 60 == 0:
        rem_txt = f"{rem // 60}시간 후"
    else:
        rem_txt = f"{rem}분 후"
    notify_msg = f"일정 알림입니다. {rem_txt}에 '{title}' 일정이 예정되어 있습니다."

    sch = globals().get("scheduler")
    if sch is None:
        print("⚠️ 일정 알림 예약 실패: scheduler 미초기화")
        return False

    # 같은 일정에 이미 걸린 옛 알림 제거 (수정·재등록 시 중복 방지)
    try:
        _removed = sch.remove_calendar_reminders(title)
        if _removed:
            print(f"🔄 기존 일정 알림 {_removed}건 제거 후 재예약 ('{title}')")
    except Exception:
        pass

    ok_any = False
    try:
        # ① 전화 알림 예약 (cal_title/cal_start: 발송 직전 삭제 여부 확인용)
        sch.add(name="일정알림", contact_name="__self_reminder__", action="call",
                schedule_time=sched_time, repeat=None,
                mission="일정 알림", message=notify_msg, report_to=MY_PHONE,
                cal_title=title, cal_start=int(start_epoch))
        # ② SMS 알림 예약
        sch.add(name="일정알림", contact_name="__self_reminder__", action="sms",
                schedule_time=sched_time, repeat=None,
                mission="일정 알림", message=notify_msg, report_to=MY_PHONE,
                cal_title=title, cal_start=int(start_epoch))
        ok_any = True
        print(f"🔔 일정 알림 예약 완료: {sched_time} 관리자에게 전화+SMS ('{title}')")
    except Exception as e:
        print(f"❌ 일정 알림 예약 실패: {e}")
    return ok_any

def _parse_calendar_datetime(speech):
    """관리자 발화에서 날짜/시간/제목/위치/설명/알림을 추출한다. AI 파서를 사용하며,
    오늘 날짜를 기준으로 상대표현('내일','모레','이번 주 금요일')도 해석하도록 유도한다.
    반환: dict 또는 None. 형식:
      {"date":"YYYY-MM-DD", "time":"HH:MM" 또는 "", "all_day":true/false,
       "title":"...", "location":"", "description":"", "reminder_min":null}"""
    import datetime as _dt
    today = _dt.date.today()
    weekday_kr = ["월","화","수","목","금","토","일"][today.weekday()]
    parse_prompt = (
        f"오늘은 {today.isoformat()} ({weekday_kr}요일)입니다.\n"
        f"다음 문장에서 일정 정보를 추출해 JSON 으로만 답하세요.\n문장: \"{speech}\"\n"
        "규칙:\n"
        "- date 는 YYYY-MM-DD (오늘/내일/모레/요일 등 상대표현은 오늘 기준으로 실제 날짜로 변환)\n"
        "- time 은 24시간 HH:MM. 시간 언급이 없으면 빈 문자열\n"
        "- all_day 는 시간 언급이 없으면 true, 있으면 false\n"
        "- title 은 일정의 핵심 이름만. '등록','등록해줘','추가','잡아줘','일정' 같은 명령어는 절대 포함하지 말 것. "
        "'설명','알림' 뒤의 내용도 title 에 넣지 말 것\n"
        "- location 은 장소. '장소는~','에서' 뒤의 지명. 없으면 빈 문자열\n"
        "- description 은 '설명은~','내용은~','메모는~','안건은~' 뒤에 오는 부가 설명. "
        "이 표현이 없으면 반드시 빈 문자열. 숫자만 있는 알림 값을 여기 넣지 말 것\n"
        "- reminder_min 은 '알림 N분 전','N분 전에 알림','N시간 전' 을 분 단위 정수로. "
        "'10분 전'→10, '30분 전'→30, '1시간 전'→60, '하루 전'→1440. 이 표현이 없으면 null. "
        "reminder 숫자를 description 에 넣지 말 것\n"
        "\n예시:\n"
        "문장: \"내일 오후 3시 회의 등록해줘 설명은 분기 실적 보고 자료 준비 알림 30분 전\"\n"
        '→ {"date":"' + (today + _dt.timedelta(days=1)).isoformat() + '","time":"15:00","all_day":false,'
        '"title":"회의","location":"","description":"분기 실적 보고 자료 준비","reminder_min":30}\n'
        "\n이제 위 문장을 같은 형식의 JSON 으로만 출력 (설명 없으면 description 은 빈 문자열, 알림 없으면 reminder_min 은 null):\n"
        '{"date":"YYYY-MM-DD","time":"HH:MM","all_day":false,"title":"...",'
        '"location":"","description":"","reminder_min":null}\n'
        "추출 불가 시 null"
    )
    raw = get_ai_reply(parse_prompt, "JSON만 출력하세요. 다른 말 금지.")
    try:
        raw = raw.strip().replace("```json", "").replace("```", "").strip()
        if raw.lower() == "null":
            return None
        data = json.loads(raw)
        if not data or not data.get("date"):
            return None
        return data
    except Exception as e:
        print(f"⚠️ 일정 파싱 실패: {e} / 원문: {raw}")
        return None

def _get_today_calendar_voice():
    """공유 폴더의 API 키로 OpenWebUI 캘린더에서 오늘 일정을 음성용 텍스트로 반환.
    실패해도 None이 아니라 원인을 설명하는 문자열을 반환한다 (가짜 일정 방지)."""
    import datetime as _dt
    # 공유 키 경로 후보 (볼륨 마운트 위치 우선, 폴백 포함)
    _key_paths = [
        "/owui-data/shared-key/openwebui_api_key",
        "/shared-key/openwebui_api_key",
    ]
    key = ""
    for _p in _key_paths:
        try:
            with open(_p, "r") as _f:
                key = _f.read().strip()
            if key:
                break
        except Exception:
            continue
    if not key:
        return ("캘린더 키가 설정되지 않았습니다. "
                "오픈웹유아이 채팅에서 캘린더 도구에 키를 입력하고 한 번 실행해 주세요.")
    url = os.getenv("OPENWEBUI_URL", "http://open-webui:8080").rstrip("/")
    today = _dt.date.today()
    start_iso = f"{today.isoformat()}T00:00:00"
    end_iso = f"{(today + _dt.timedelta(days=1)).isoformat()}T00:00:00"
    try:
        # 보안: netrc/환경 자격증명 비활성화(CVE-2024-47081) + 리다이렉트 차단
        _sess = requests.Session()
        _sess.trust_env = False
        r = _sess.get(
            f"{url}/api/v1/calendars/events",
            headers={"Authorization": f"Bearer {key}"},
            params={"start": start_iso, "end": end_iso},
            timeout=30, allow_redirects=False,
        )
    except Exception:
        return "캘린더 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요."
    if r.status_code in (401, 403):
        return ("캘린더 키 인증에 실패했습니다. "
                "키가 만료되었을 수 있으니 새 키로 다시 설정해 주세요.")
    if r.status_code >= 400:
        return "일정을 가져오지 못했습니다. 잠시 후 다시 시도해 주세요."
    try:
        events = r.json()
    except Exception:
        return "일정 정보를 해석하지 못했습니다."

    def _fmt(ns, all_day):
        if not ns:
            return ""
        try:
            ns = int(ns)
        except (TypeError, ValueError):
            return ""
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
            return "종일"
        return d.strftime("%H시 %M분")

    if not events:
        return f"{today.month}월 {today.day}일 오늘은 예정된 일정이 없습니다."

    def _k(e):
        try:
            return int(e.get("start_at") or 0)
        except (TypeError, ValueError):
            return 0

    events = sorted(events, key=_k)
    parts = [f"{today.month}월 {today.day}일 오늘의 일정입니다"]
    for e in events:
        when = _fmt(e.get("start_at"), e.get("all_day", False))
        title = e.get("title") or "제목 없음"
        loc = e.get("location")
        seg = f"{when} {title}" if when else title
        if loc:
            seg += f", 장소는 {loc}"
        parts.append(seg)
    return ". ".join(parts) + "."


def process_admin_command(speech, caller, bargein_note=""):
    import datetime as _dt2
    # ════════════════════════════════════════════
    # 📅 캘린더 일정 "등록" — "○○ 등록해줘/잡아줘/추가해줘"
    #    (일정/약속/스케줄 + 등록성 동사가 함께 있을 때만 등록으로 처리)
    # ════════════════════════════════════════════
    _cal_add_verbs = ["등록", "잡아", "추가", "넣어", "잡아줘"]
    _cal_add_nouns = ["일정", "약속", "스케줄", "미팅", "회의"]
    if any(n in speech for n in _cal_add_nouns) and any(v in speech for v in _cal_add_verbs):
        info = _parse_calendar_datetime(speech)
        if not info:
            return "언제, 무슨 일정인지 이해하지 못했습니다. 예를 들어 '12월 25일 오후 3시에 회의 등록해줘'처럼 말씀해 주세요."
        try:
            d = _dt2.date.fromisoformat(info["date"])
        except Exception:
            return "날짜를 정확히 이해하지 못했습니다. 다시 말씀해 주세요."
        _t = (info.get("time") or "").strip()
        all_day = bool(info.get("all_day")) or not _t
        title = (info.get("title") or "일정").strip()
        if all_day:
            start_dt = _dt2.datetime(d.year, d.month, d.day, 0, 0)
        else:
            try:
                hh, mm = _t.split(":")
                start_dt = _dt2.datetime(d.year, d.month, d.day, int(hh), int(mm))
            except Exception:
                start_dt = _dt2.datetime(d.year, d.month, d.day, 0, 0)
                all_day = True
        start_epoch = int(start_dt.timestamp())
        _loc = (info.get("location") or "").strip()
        _desc = (info.get("description") or "").strip()
        _rem = info.get("reminder_min")
        try:
            _rem = int(_rem) if _rem is not None and str(_rem).strip() != "" else None
        except (TypeError, ValueError):
            _rem = None
        ok, err = _create_calendar_event(
            title, start_epoch, all_day=all_day,
            location=_loc, description=_desc, reminder_min=_rem,
        )
        if ok:
            when_txt = f"{d.month}월 {d.day}일"
            if not all_day:
                when_txt += f" {start_dt.hour}시"
                if start_dt.minute:
                    when_txt += f" {start_dt.minute}분"
            _extra = ""
            if _loc:
                _extra += f", 장소는 {_loc}"
            if _rem is not None:
                if _rem >= 1440 and _rem % 1440 == 0:
                    _extra += f", 알림은 {_rem // 1440}일 전"
                elif _rem >= 60 and _rem % 60 == 0:
                    _extra += f", 알림은 {_rem // 60}시간 전"
                else:
                    _extra += f", 알림은 {_rem}분 전"
            if _desc:
                _extra += f", 설명도 함께"
            # 🔔 알림 시각에 관리자에게 전화+SMS 예약
            _notified = False
            if _rem is not None:
                _notified = _schedule_event_reminder(title, start_epoch, _rem)
            if _notified:
                _extra += ". 알림 시각에 전화와 문자로 알려드릴게요"
            return f"{when_txt}에 '{title}' 일정을 등록했습니다{_extra}."
        return err

    # ════════════════════════════════════════════
    # 📅 캘린더 "특정 날짜" 조회 — "12월 25일 일정 알려줘", "내일 일정"
    # ════════════════════════════════════════════
    _cal_query_nouns = ["일정", "약속", "스케줄", "뭐 있"]
    _has_specific_date = any(x in speech for x in ["월", "내일", "모레", "글피", "다음 주", "이번 주", "다음주", "이번주"])
    _is_today_word = any(x in speech for x in ["오늘", "오늘일정"])
    if (not _is_today_word) and _has_specific_date and any(n in speech for n in _cal_query_nouns):
        info = _parse_calendar_datetime(speech)
        if info and info.get("date"):
            try:
                d = _dt2.date.fromisoformat(info["date"])
                return _get_calendar_events_voice(d)
            except Exception:
                pass
        return "어느 날짜의 일정인지 정확히 이해하지 못했습니다. 예를 들어 '12월 25일 일정 알려줘'처럼 말씀해 주세요."

    # ════════════════════════════════════════════
    # 📅 캘린더 (오늘 일정) — 공유 키로 OpenWebUI 캘린더 조회
    #    채팅 도구 밸브에 입력한 키를 공유 폴더에서 읽어 사용
    # ════════════════════════════════════════════
    _cal_kw = ["오늘 일정", "오늘일정", "오늘 스케줄", "오늘 약속",
               "일정 알려", "일정 뭐", "스케줄 알려", "오늘 뭐 있"]
    if any(k in speech for k in _cal_kw):
        _cal = _get_today_calendar_voice()
        # 캘린더 의도면 항상 캘린더 응답을 반환 (실패해도 원인 안내).
        # AI 일반 처리로 넘기지 않으므로 '가짜 일정'이 나오지 않는다.
        if _cal:
            return _cal
        return "오늘 일정을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."

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
                        _record_sms()  # 하루 문자 카운터 증가
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
            # ── 1단계: JSON 정확 이름 매칭 ──
            matched_name = None
            matched_number = None
            for name, number in CONTACTS.items():
                if name in speech:
                    matched_name = name
                    matched_number = number
                    break
            # ── 2단계: JSON 매칭 실패 시 Qdrant 의미 검색 폴백 ──
            if not matched_name:
                try:
                    qdrant_results = search_contacts_qdrant(speech, top_k=1)
                    if qdrant_results:
                        matched_name = qdrant_results[0]["name"]
                        matched_number = qdrant_results[0]["number"]
                        print(f"🔍 Qdrant 폴백 검색: '{speech}' → {matched_name}")
                except Exception as e:
                    print(f"⚠️ Qdrant 폴백 실패: {e}")
            if matched_name and matched_number:
                name = matched_name
                number = matched_number
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

    # 일반 대화: 끼어들기 맥락이 있으면 앞에 덧붙여 AI가 새 질문에 집중하게 함
    _final_input = (bargein_note + "\n\n" + speech) if bargein_note else speech
    return get_ai_reply(_final_input, ADMIN_COMMAND_PROMPT, call_sid=request.form.get("CallSid", caller))

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
    tts_voice = get_tts_voice(lang)
    tts_lang = get_twilio_lang(lang)
    tts_voice = get_tts_voice(lang)
    print(f"📞 수신 전화: {caller} (언어: {lang})")

    if is_blocked(caller):
        print(f"🚫 차단된 번호: {caller}")
        response.say(get_msg("BLOCKED", lang), voice=tts_voice, language=tts_lang)
        response.hangup()
        return Response(str(response), mimetype="text/xml")

    if is_pin_locked(caller):
        print(f"🔒 PIN 잠금 번호: {caller}")
        response.say(get_msg("BLOCKED_PIN", lang), voice=tts_voice, language=tts_lang)
        response.hangup()
        return Response(str(response), mimetype="text/xml")

    if BOT_MODE == "3":
        response.say(get_msg("PLEASE_WAIT", lang), voice=tts_voice, language=tts_lang)
        dial = Dial(caller_id=TWILIO_PHONE)
        dial.number(MY_PHONE)
        response.append(dial)
        return Response(str(response), mimetype="text/xml")

    # ── 🎙️ 진짜 실시간 모드: 일반(비관리자) 수신전화를 Media Stream 으로 처리 ──
    #    관리자 본인은 명령/PIN 흐름이 필요하므로 기존 turn-based 유지.
    if REALTIME_MODE and not is_admin(caller):
        _rt_greeting = get_msg("GREETING_DEFAULT", lang) or "여보세요, 안녕하세요. 무엇을 도와드릴까요?"
        _rt_sys = get_system_prompt(INBOUND_SYSTEM_PROMPTS, lang, INBOUND_SYSTEM_PROMPT)
        print(f"🎙️ 실시간 스트림 연결(수신): {caller}")
        return Response(
            build_stream_twiml(name=caller, number=caller, direction="inbound",
                               greeting=_rt_greeting, system_prompt=_rt_sys),
            mimetype="text/xml")

    if is_admin(caller):
        print(f"✅ 관리자 연결: {caller}")
        # 📞 월 통화시간 한도 체크 (100% 초과 시 차단)
        _call_ok, _call_reason = can_receive_admin_call()
        if not _call_ok:
            print(f"🚫 월 통화 한도 초과 — 관리자 통화 차단: {_call_reason}")
            response.say(
                f"죄송합니다. {_call_reason}. 다음 달에 다시 이용해 주세요.",
                voice=tts_voice, language=tts_lang
            )
            response.hangup()
            return Response(str(response), mimetype="text/xml")
        gather = Gather(input="speech dtmf", barge_in=True, numDigits=1, speechModel="phone_call", enhanced="true", action=f"{SERVER_DOMAIN}/respond",
                        language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout=str(SPEECH_TIMEOUT_INBOUND))
        gather.say(get_msg("GREETING_ADMIN", lang), voice=tts_voice, language=tts_lang)
        response.append(gather)
        response.say(get_msg("NO_COMMAND", lang), voice=tts_voice, language=tts_lang)
        return Response(str(response), mimetype="text/xml")

    # 고객 상담 모드: 미등록(고객) 번호는 일반 AI 상담으로 연결
    # (캘린더·SMS·명령 등 관리자 전용 기능은 respond()에서 is_admin 으로 분리 차단됨)
    print(f"📞 고객 상담 연결 (일반 응대): {caller}")
    gather = Gather(input="speech dtmf", barge_in=True, numDigits=1, speechModel="phone_call", enhanced="true", action=f"{SERVER_DOMAIN}/respond",
                    language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout=str(SPEECH_TIMEOUT_INBOUND))
    gather.say(get_msg("GREETING_DEFAULT", lang), voice=tts_voice, language=tts_lang)
    # 0번 안내: 기능(OPERATOR_TRANSFER_ENABLED)이 켜져 있고 안내(OPERATOR_HINT_ENABLED)도 켜진 경우만
    if OPERATOR_TRANSFER_ENABLED and OPERATOR_HINT_ENABLED:
        gather.say(get_msg("OPERATOR_HINT", lang), voice=tts_voice, language=tts_lang)
    response.append(gather)
    response.say(get_msg("NO_COMMAND", lang), voice=tts_voice, language=tts_lang)
    return Response(str(response), mimetype="text/xml")


@app.route("/verify-pin", methods=["POST"])
@validate_twilio_request
def verify_pin():
    # 관리자가 민감 명령 실행을 위해 입력한 PIN을 검증한다.
    # 성공 시: 이 통화를 인증 상태로 표시하고, 보류해 둔 원래 명령을 실행해 응답.
    # 실패 시: 실패 횟수 기록(3회 누적 시 30분 잠금) 후 재요청 또는 종료.
    caller    = request.form.get("From", "")
    digits    = request.form.get("Digits", "").strip()
    call_sid  = request.form.get("CallSid", caller)
    response  = VoiceResponse()
    lang      = get_lang_for_call(caller=caller)
    tts_lang  = get_twilio_lang(lang)
    tts_voice = get_tts_voice(lang)

    # 등록된 관리자만 PIN 인증 대상
    if not is_admin(caller):
        print(f"🚫 verify-pin: 미등록 번호 차단 [{caller}]")
        response.say(get_msg("NOT_ADMIN", lang), voice=tts_voice, language=tts_lang)
        response.hangup()
        return Response(str(response), mimetype="text/xml")

    # 잠긴 번호는 차단
    if is_pin_locked(caller):
        response.say(get_msg("BLOCKED_PIN", lang), voice=tts_voice, language=tts_lang)
        response.hangup()
        return Response(str(response), mimetype="text/xml")

    # ── PIN 일치 확인 ──
    if digits and digits == ADMIN_PIN:
        reset_pin_failure(caller)
        mark_pin_verified(call_sid)
        print(f"✅ PIN 인증 성공 [{caller}] (call_sid={call_sid})")

        # 보류해 둔 원래 명령을 이어서 실행
        pending = _pin_pending.pop(call_sid, "")
        if pending:
            ai_reply = process_admin_command(pending, caller)
        else:
            ai_reply = get_msg("PIN_OK", lang)
        print(f"🤖 [{caller}] {ai_reply}")
        mark_ai_speaking(call_sid, ai_reply, lang=lang)

        gather = Gather(input="speech dtmf", barge_in=True, numDigits=1,
                        speechModel="phone_call", enhanced="true",
                        action=f"{SERVER_DOMAIN}/respond",
                        language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout=str(SPEECH_TIMEOUT_INBOUND))
        gather.say(ai_reply, voice=tts_voice, language=tts_lang)
        response.append(gather)
        response.say(get_msg("BYE_INBOUND", lang), voice=tts_voice, language=tts_lang)
        return Response(str(response), mimetype="text/xml")

    # ── PIN 불일치 → 실패 기록 ──
    fail_count = record_pin_failure(caller)
    print(f"❌ PIN 인증 실패 [{caller}] ({fail_count}/{PIN_MAX_FAIL})")

    if fail_count >= PIN_MAX_FAIL:
        # 잠금 발동 → 종료
        response.say(get_msg("BLOCKED_PIN", lang), voice=tts_voice, language=tts_lang)
        response.hangup()
        return Response(str(response), mimetype="text/xml")

    # 재시도 요청 (보류 명령 유지)
    _pin_len = max(1, len(ADMIN_PIN))
    gather = Gather(input="dtmf", numDigits=_pin_len, finishOnKey="#",
                    action=f"{SERVER_DOMAIN}/verify-pin",
                    language=tts_lang, timeout=TIMEOUT_INBOUND)
    gather.say(get_msg("PIN_RETRY", lang), voice=tts_voice, language=tts_lang)
    response.append(gather)
    response.say(get_msg("PIN_TIMEOUT", lang), voice=tts_voice, language=tts_lang)
    response.hangup()
    return Response(str(response), mimetype="text/xml")


@app.route("/respond", methods=["POST"])
@validate_twilio_request
def respond():
    user_speech = request.form.get("SpeechResult", "").strip()
    caller      = request.form.get("From", "")
    digits      = request.form.get("Digits", "").strip()  # 키패드 입력
    response    = VoiceResponse()
    lang        = get_lang_for_call(caller=caller)
    tts_lang    = get_twilio_lang(lang)
    tts_voice   = get_tts_voice(lang)

    print(f"🗣️ [{caller}] {user_speech}" + (f" [키패드:{digits}]" if digits else ""))

    # ── 키패드 0번 → 관리자(사람) 직통 연결 ──
    # (ai_config의 OPERATOR_TRANSFER_ENABLED 로 기능 자체를 켜고 끔)
    if OPERATOR_TRANSFER_ENABLED and digits == "0" and MY_PHONE:
        print(f"☎️ 0번 입력 → 관리자 연결 [{caller}]")
        response.say(get_msg("TRANSFER", lang), voice=tts_voice, language=tts_lang)
        dial = Dial(caller_id=TWILIO_PHONE)
        dial.number(MY_PHONE)
        response.append(dial)
        return Response(str(response), mimetype="text/xml")

    if not user_speech:
        gather = Gather(input="speech dtmf", barge_in=True, numDigits=1, speechModel="phone_call", enhanced="true", action=f"{SERVER_DOMAIN}/respond",
                        language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout=str(SPEECH_TIMEOUT_INBOUND))
        gather.say(get_msg("NOT_HEARD", lang), voice=tts_voice, language=tts_lang)
        response.append(gather)
        return Response(str(response), mimetype="text/xml")

    # 너무 짧거나 불명확한 음성 → 천천히 말씀해 달라고 요청
    sd_count = inbound_slow_down.get(caller, 0)
    if len(user_speech) <= SLOW_DOWN_MIN_CHARS and sd_count < SLOW_DOWN_MAX:
        inbound_slow_down[caller] = sd_count + 1
        gather = Gather(input="speech dtmf", barge_in=True, numDigits=1, speechModel="phone_call", enhanced="true", action=f"{SERVER_DOMAIN}/respond",
                        language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout=str(SPEECH_TIMEOUT_INBOUND))
        gather.say(get_msg("SLOW_DOWN", lang), voice=tts_voice, language=tts_lang)
        response.append(gather)
        print(f"🐢 천천히 요청 [{caller}] ({sd_count + 1}회): '{user_speech}'")
        return Response(str(response), mimetype="text/xml")

    # 음성으로 담당자 연결 요청 (ai_config의 OPERATOR_VOICE_ENABLED / KEYWORDS로 제어)
    if OPERATOR_VOICE_ENABLED and MY_PHONE and any(kw in user_speech for kw in OPERATOR_VOICE_KEYWORDS):
        print(f"🗣️→☎️ 음성 담당자 요청 → 관리자 연결 [{caller}]")
        response.say(get_msg("TRANSFER", lang), voice=tts_voice, language=tts_lang)
        dial = Dial(caller_id=TWILIO_PHONE)
        dial.number(MY_PHONE)
        response.append(dial)
        return Response(str(response), mimetype="text/xml")

    call_sid = request.form.get("CallSid", caller)  # 통화별 히스토리 키

    # ── 끼어들기(barge-in) 감지 ──
    _confidence = request.form.get("Confidence", "")
    _interrupted = detect_barge_in(call_sid, confidence=_confidence)
    if _interrupted:
        mark_history_interrupted(call_sid)
        print(f"✋ 끼어들기 감지 [{caller}]: '{user_speech}'")

    # ── 수신전화 세션 추적 (관리자 제외) ──
    if not is_admin(caller):
        if call_sid not in inbound_sessions:
            inbound_sessions[call_sid] = {
                "caller": caller,
                "start": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "history": [],
                "_timer": None,
                "report_sent": False
            }

    # ── 끼어들기 맥락 지시문 (감지 시에만) ──
    # 지시문 내용은 ai_config.py 의 BARGEIN_NOTE 로 조절 가능
    _bargein_note = ""
    if _interrupted:
        _bargein_note = "\n\n" + BARGEIN_NOTE

    if is_admin(caller):
        # ── 민감 명령(전화/문자/저장/예약) 실행 전 PIN 확인 ──
        # 통화당 1회 인증하면 통화 내내 유효. 조회·일반대화는 PIN 불필요.
        if ADMIN_PIN_REQUIRED and _is_sensitive_command(user_speech) and not is_pin_verified(call_sid):
            _pin_pending[call_sid] = user_speech  # PIN 입력 후 재실행할 원래 명령 저장
            print(f"🔐 민감 명령 감지 → PIN 요청 [{caller}]: '{user_speech}'")
            _pin_len = max(1, len(ADMIN_PIN))
            gather = Gather(input="dtmf", numDigits=_pin_len, finishOnKey="#",
                            action=f"{SERVER_DOMAIN}/verify-pin",
                            language=tts_lang, timeout=TIMEOUT_INBOUND)
            gather.say(get_msg("PIN_REQUEST", lang), voice=tts_voice, language=tts_lang)
            response.append(gather)
            # 시간 초과로 PIN 미입력 시
            response.say(get_msg("PIN_TIMEOUT", lang), voice=tts_voice, language=tts_lang)
            response.hangup()
            return Response(str(response), mimetype="text/xml")
        ai_reply = process_admin_command(user_speech, caller, bargein_note=_bargein_note)
    else:
        # ── 진행 중 통화로 등록 (실시간 귓속말 대상) ──
        if call_sid not in _active_calls:
            _cname = get_contact_name(caller) if 'get_contact_name' in globals() else caller
            register_active_call(call_sid, name=_cname or caller, number=caller, direction="inbound")
        update_active_call(call_sid, last_speech=user_speech)

        # ── RAG: 상대방 질문에 관련 문서 참고 ──
        rag_ref = rag_lookup(user_speech)
        rag_prompt = ""
        if rag_ref:
            rag_prompt = f"\n\n참고자료 (답변에 자연스럽게 활용하세요):\n{rag_ref}\n\n상대방 질문: {user_speech}"
        else:
            rag_prompt = user_speech
        if _bargein_note:
            rag_prompt = _bargein_note + "\n\n" + rag_prompt

        # ── 🤫 실시간 귓속말 주입 (관리자 지시를 시스템 프롬프트 최우선으로) ──
        _sys_prompt = get_system_prompt(INBOUND_SYSTEM_PROMPTS, lang, INBOUND_SYSTEM_PROMPT)
        _whisper = pop_whispers(call_sid)
        if _whisper:
            _sys_prompt = _whisper + "\n\n" + (_sys_prompt or "")

        # ── 🧠 기억의 앵커: 통화 초반에만 과거 회상 주입 (매 턴 X → 자연스럽게) ──
        try:
            if len(get_call_history(call_sid)) <= 2:
                _mem = build_memory_prompt(caller, query_text=user_speech)
                if _mem:
                    _sys_prompt = (_sys_prompt or "") + "\n\n" + _mem
        except Exception as _me:
            print(f"⚠️ 기억 회상 훅 오류(무시): {_me}")

        ai_reply = get_ai_reply(rag_prompt, _sys_prompt, call_sid=call_sid)
        update_active_call(call_sid, last_ai=ai_reply)

    print(f"🤖 [{caller}] {ai_reply}")

    # ── 끼어들기 판단용: AI가 이 답변을 낭독하기 시작함을 기록 ──
    mark_ai_speaking(call_sid, ai_reply, lang=lang)

    # ── 수신전화 대화 기록 + 보고 타이머 갱신 ──
    if not is_admin(caller) and call_sid in inbound_sessions:
        inbound_sessions[call_sid]["history"].append({"user": user_speech, "ai": ai_reply})
        # 이전 타이머 취소 후 새 타이머 설정 (마지막 대화 후 60초 무응답 시 보고)
        prev_timer = inbound_sessions[call_sid].get("_timer")
        if prev_timer:
            prev_timer.cancel()
        t = threading.Timer(_inbound_report_delay, send_inbound_report, args=[call_sid])
        inbound_sessions[call_sid]["_timer"] = t
        t.start()

    gather = Gather(input="speech dtmf", barge_in=True, numDigits=1, speechModel="phone_call", enhanced="true", action=f"{SERVER_DOMAIN}/respond",
                    language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout=str(SPEECH_TIMEOUT_INBOUND))
    gather.say(ai_reply, voice=tts_voice, language=tts_lang)
    response.append(gather)
    response.say(get_msg("BYE_INBOUND", lang), voice=tts_voice, language=tts_lang)
    return Response(str(response), mimetype="text/xml")


@app.route("/voice-out-simple", methods=["POST"])
@validate_twilio_request
def voice_out_simple():
    response = VoiceResponse()
    lang     = detect_lang(MY_PHONE)
    tts_lang = get_twilio_lang(lang)
    tts_voice = get_tts_voice(lang)
    tts_lang = get_twilio_lang(lang)
    tts_voice = get_tts_voice(lang)
    gather = Gather(input="speech dtmf", barge_in=True, numDigits=1, speechModel="phone_call", enhanced="true", action=f"{SERVER_DOMAIN}/respond-admin",
                    language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout=str(SPEECH_TIMEOUT_ADMIN))
    gather.say(get_msg("GREETING_ADMIN", lang), voice=tts_voice, language=tts_lang)
    response.append(gather)
    response.say(get_msg("BYE_ADMIN_SIMPLE", lang), voice=tts_voice, language=tts_lang)
    return Response(str(response), mimetype="text/xml")


@app.route("/respond-admin", methods=["POST"])
@validate_twilio_request
def respond_admin():
    user_speech = request.form.get("SpeechResult", "").strip()
    response    = VoiceResponse()
    lang        = detect_lang(MY_PHONE)
    tts_lang    = get_twilio_lang(lang)
    tts_voice   = get_tts_voice(lang)

    if not user_speech:
        gather = Gather(input="speech dtmf", barge_in=True, numDigits=1, speechModel="phone_call", enhanced="true", action=f"{SERVER_DOMAIN}/respond-admin",
                        language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout=str(SPEECH_TIMEOUT_ADMIN))
        gather.say(get_msg("NOT_HEARD_ADMIN", lang), voice=tts_voice, language=tts_lang)
        response.append(gather)
        return Response(str(response), mimetype="text/xml")

    print(f"🗣️ [관리자 아웃바운드] {user_speech}")
    ai_reply = process_admin_command(user_speech, MY_PHONE)
    print(f"🤖 [관리자 아웃바운드] {ai_reply}")

    gather = Gather(input="speech dtmf", barge_in=True, numDigits=1, speechModel="phone_call", enhanced="true", action=f"{SERVER_DOMAIN}/respond-admin",
                    language=tts_lang, timeout=TIMEOUT_INBOUND, speechTimeout=str(SPEECH_TIMEOUT_ADMIN))
    gather.say(ai_reply, voice=tts_voice, language=tts_lang)
    response.append(gather)
    response.say(get_msg("BYE_ADMIN_OUT", lang), voice=tts_voice, language=tts_lang)
    return Response(str(response), mimetype="text/xml")


@app.route("/voice-out-welfare", methods=["POST"])
@validate_twilio_request
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
    tts_voice = get_tts_voice(lang)
    tts_lang = get_twilio_lang(lang)
    tts_voice = get_tts_voice(lang)
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

    # ── 🎙️ 진짜 실시간 모드: 대리·안부전화를 Media Stream 으로 처리 ──
    if REALTIME_MODE:
        # 세션에 첫 인사 기록 (보고용 맥락 유지)
        if call_sid in outbound_sessions:
            outbound_sessions[call_sid]["full_greeting"] = full_greeting
        _rt_sys = (
            f"당신은 {contact_name}님에게 전화를 건 따뜻한 AI 비서입니다. 임무: {mission}. "
            "한 번에 1~2문장으로 자연스럽게 말하세요. AI라는 티를 내지 마세요. "
            "관리자가 실시간 지시를 주면 그 내용을 자연스럽게 반영하세요."
        )
        _rec_prefix = ""
        if ENABLE_CALL_RECORDING:
            _rec_prefix = {"ko": "안내 말씀드립니다. 이 통화는 품질 향상을 위해 녹음됩니다. ",
                           "en": "Please note, this call is being recorded. ",
                           "ja": "この通話は録音されます。 ",
                           "zh": "本次通话将被录音。 "}.get(lang, "")
        print(f"🎙️ 실시간 스트림 연결(대리전화): {contact_name}")
        return Response(
            build_stream_twiml(name=contact_name, number=callee_number, direction="outbound",
                               greeting=_rec_prefix + full_greeting, system_prompt=_rt_sys),
            mimetype="text/xml")

    action_url = f"{SERVER_DOMAIN}/respond-out"
    try:
        speech_to = SPEECH_TIMEOUT_OUTBOUND
    except NameError:
        speech_to = "auto"
    gather = Gather(input="speech dtmf", barge_in=True, numDigits=1, speechModel="phone_call", enhanced="true", action=action_url,
                    language=tts_lang, timeout=TIMEOUT_OUTBOUND, speechTimeout=str(speech_to))
    # 📼 녹음 활성화 시 안내 멘트 (법적 고지 의무)
    if ENABLE_CALL_RECORDING:
        recording_notice = {"ko": "안내 말씀드립니다. 이 통화는 품질 향상을 위해 녹음됩니다.",
                            "en": "Please note, this call is being recorded for quality purposes.",
                            "ja": "この通話は品質向上のため録音されます。",
                            "zh": "为了提高服务质量，本次通话将被录音。"}.get(lang, "This call is being recorded.")
        gather.say(recording_notice, voice=tts_voice, language=tts_lang)
        gather.pause(length=1)
    gather.say(full_greeting, voice=tts_voice, language=tts_lang)
    response.append(gather)

    # 첫 인사를 session에 저장 (AI가 맥락을 잃지 않도록)
    if call_sid in outbound_sessions:
        outbound_sessions[call_sid]["full_greeting"] = full_greeting
        outbound_sessions[call_sid]["lang"] = lang
        outbound_sessions[call_sid]["call_start_time"] = time.time()  # 통화 시작 시간 기록
        print(f"⏱️ 통화 타이머 시작: {contact_name} (4분 제한)")

    response.say(get_msg("TIMEOUT_WELFARE", lang).format(contact_name=contact_name), voice=tts_voice, language=tts_lang)
    response.hangup()
    # 통화 완전 종료 후 보고 (completed 콜백에서 처리)
    if call_sid in outbound_sessions:
        outbound_sessions[call_sid]["pending_summary"] = True
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
    tts_voice = get_tts_voice(lang)
    tts_lang = get_twilio_lang(lang)
    tts_voice = get_tts_voice(lang)

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
            gather = Gather(input="speech dtmf", barge_in=True, numDigits=1,
                            action=f"{SERVER_DOMAIN}/respond-out",
                            language=tts_lang, timeout=TIMEOUT_OUTBOUND, speechTimeout=str(speech_to))
            # 첫 번째는 "못 들었어요", 두 번째부터는 "기다릴게요"
            if patience == 0:
                gather.say(get_msg("NOT_HEARD_OUT", lang), voice=tts_voice, language=tts_lang)
            else:
                msg = get_msg("WAIT_THINKING", lang) or get_msg("ENCOURAGE_SPEAK", lang) or get_msg("NOT_HEARD_OUT", lang)
                gather.say(msg, voice=tts_voice, language=tts_lang)
            response.append(gather)
            print(f"⏳ 인내심 대기 ({patience + 1}/{max_patience}회): 음성 없음")
            return Response(str(response), mimetype="text/xml")
        else:
            # 최대 인내심 초과 → 기존 대화 내용으로 보고 후 종료
            response.say(get_msg("TIMEOUT_WELFARE", lang).format(contact_name=contact_name), voice=tts_voice, language=tts_lang)
            response.hangup()
            # 통화 완전 종료 후 보고 (completed 콜백에서 처리)
            if call_sid in outbound_sessions:
                outbound_sessions[call_sid]["pending_summary"] = True
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
            gather = Gather(input="speech dtmf", barge_in=True, numDigits=1,
                            action=f"{SERVER_DOMAIN}/respond-out",
                            language=tts_lang, timeout=TIMEOUT_OUTBOUND, speechTimeout=str(speech_to))
            msg = get_msg("ENCOURAGE_SPEAK", lang) or get_msg("WAIT_THINKING", lang)
            gather.say(msg, voice=tts_voice, language=tts_lang)
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
            gather = Gather(input="speech dtmf", barge_in=True, numDigits=1,
                            action=f"{SERVER_DOMAIN}/respond-out",
                            language=tts_lang, timeout=TIMEOUT_OUTBOUND, speechTimeout=str(speech_to))
            # 지금까지 모은 조각을 확인
            confirm_msg = get_msg("FRAGMENT_CONFIRM", lang)
            if confirm_msg and "{fragment}" in confirm_msg:
                gather.say(confirm_msg.format(fragment=accumulated), voice=tts_voice, language=tts_lang)
            else:
                gather.say(get_msg("ENCOURAGE_SPEAK", lang), voice=tts_voice, language=tts_lang)
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

    # ── 통화 시간 제한 체크 (3분30초 정리 멘트 / 4분 강제 종료) ──────────
    call_start = session.get("call_start_time")
    if call_start:
        elapsed = time.time() - call_start
        print(f"⏱️ 통화 경과 시간: {int(elapsed)}초 ({contact_name})")

        # 4분(240초) 이상 → 즉시 강제 종료 (Twilio time_limit=240 백업)
        if elapsed >= 240:
            session["history"].append({"ai": "(시간 초과 강제 종료)", "user": user_speech})
            response.say(
                f"{contact_name}님, 통화 시간이 초과되어 여기서 마무리하겠습니다. 감사합니다. 안녕히 계세요.",
                voice=tts_voice, language=tts_lang
            )
            response.hangup()
            if call_sid in outbound_sessions:
                outbound_sessions[call_sid]["pending_summary"] = True
                outbound_sessions[call_sid]["time_limit_ended"] = True
            print(f"🚫 4분 초과 강제 종료: {contact_name} ({int(elapsed)}초)")
            return Response(str(response), mimetype="text/xml")

        # 3분 30초(210초) 이상 → 대화 맥락 요약 후 정리 멘트, 담당자 연결 안내
        if elapsed >= 210:
            # 지금까지 대화 내용 정리
            history_for_summary = "\n".join([
                f"AI: {h['ai']}\n{contact_name}: {h['user']}"
                for h in session["history"]
            ])
            if user_speech:
                history_for_summary += f"\n{contact_name}: {user_speech}"

            wrapup_prompt = f"""당신은 {contact_name}님과 전화 통화 중인 AI 어시스턴트입니다.
임무: {mission}
지금까지 대화:
{history_for_summary}

통화 시간이 거의 다 되었습니다. 다음을 한 번에 자연스럽게 말해주세요:
1. 지금까지 대화 내용의 핵심을 간단히 언급 (1문장)
2. "지금까지 말씀해주신 내용을 담당자에게 보고드리겠습니다" 라는 취지의 말
3. "더 자세한 내용은 담당자가 직접 연락드릴 수 있도록 전달하겠습니다" 라는 안내
4. 따뜻한 마무리 인사

전체 3~4문장으로 자연스럽게 이어서 답하세요."""

            wrapup_reply = get_ai_reply(wrapup_prompt,
                f"당신은 따뜻하고 친근한 AI 전화 어시스턴트입니다. {contact_name}님과 전화 통화 중입니다. "
                "통화를 마무리하는 정리 멘트를 3~4문장으로 답하세요. "
                "AI라고 밝히지 말고, 자연스럽게 비서처럼 말하세요.")

            session["history"].append({"ai": wrapup_reply, "user": user_speech})
            response.say(wrapup_reply, voice=tts_voice, language=tts_lang)
            response.pause(length=1)
            response.hangup()
            if call_sid in outbound_sessions:
                outbound_sessions[call_sid]["pending_summary"] = True
                outbound_sessions[call_sid]["time_limit_ended"] = True
            print(f"⏰ 3분30초 정리 멘트 후 종료: {contact_name} ({int(elapsed)}초)")
            return Response(str(response), mimetype="text/xml")
    # ── 통화 시간 제한 체크 끝 ──────────────────────────

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

    # ── RAG: 안부전화 발신에서는 스킵 (속도 최적화) ──
    # 수신전화(/respond)에서는 RAG 정상 작동, 채팅 Tool도 별개로 정상 작동
    rag_section = ""

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

    next_prompt = f"""전화 통화 중. 상대: {contact_name}. 임무: {mission}{context_info}
대화:
{history_text if history_text else "(시작)"}
{contact_name}: {user_speech}{rag_section}{min_turns_rule}

상대방 말에 공감하고 1문장으로 답하세요. 불완전한 말도 문맥으로 이해하세요.
대화 3턴 이상 + 임무 완료 시 "DONE:"으로 마무리 인사. 아니면 다음 질문.
답변:"""

    # ── 🤫 실시간 귓속말 주입 (대리통화 중 관리자 지시 반영) ──
    #    이 통화를 진행 중 목록에 등록/갱신하고, 대기 지시를 시스템 프롬프트 최우선으로.
    if call_sid not in _active_calls:
        register_active_call(call_sid, name=contact_name, number=session.get("number", ""), direction="outbound")
    update_active_call(call_sid, last_speech=user_speech)

    dialogue_rules = OUTBOUND_DIALOGUE_RULES_MAP.get(lang, OUTBOUND_DIALOGUE_RULES) if OUTBOUND_DIALOGUE_RULES_MAP else OUTBOUND_DIALOGUE_RULES
    _out_sys = f"당신은 {contact_name}님과 전화 중인 따뜻한 AI 어시스턴트입니다.\n" + dialogue_rules + """
핵심 규칙: 이전 대화 맥락에 맞게, 공감 먼저, 반드시 1문장만."""
    _whisper_out = pop_whispers(call_sid)
    if _whisper_out:
        # 대리통화는 1문장 규칙이 있으므로, 지시가 있을 땐 자연스럽게 녹이도록 최우선 안내
        _out_sys = _whisper_out + "\n\n" + _out_sys

    # ── 🧠 기억의 앵커: 대리전화 초반에만 과거 회상 주입 ──
    try:
        if len(session.get("history", [])) <= 1:
            _mem = build_memory_prompt(session.get("number", ""), name=contact_name, query_text=user_speech)
            if _mem:
                _out_sys = _out_sys + "\n\n" + _mem
    except Exception as _me:
        print(f"⚠️ 기억 회상 훅 오류(무시): {_me}")

    ai_next = get_ai_reply(next_prompt, _out_sys)
    update_active_call(call_sid, last_ai=ai_next.replace("DONE:", "").strip())

    session["history"].append({"ai": ai_next.replace("DONE:", "").strip(), "user": user_speech})

    if ai_next.startswith("DONE:"):
        farewell = ai_next.replace("DONE:", "").strip()
        response.say(farewell, voice=tts_voice, language=tts_lang)
        response.pause(length=1)
        response.say(get_msg("DONE_REPORT", lang).format(contact_name=contact_name), voice=tts_voice, language=tts_lang)
        response.hangup()
        # 통화 완전 종료 후 보고 (call_status completed 콜백에서 처리)
        # summary_sent=False 유지 → Twilio가 completed 콜백 보낼 때 보고
        if call_sid in outbound_sessions:
            outbound_sessions[call_sid]["pending_summary"] = True
        print(f"📋 통화 종료 대기 중 — completed 콜백 후 보고 예정: {contact_name}")
    else:
        action_url = f"{SERVER_DOMAIN}/respond-out"
        gather = Gather(input="speech dtmf", barge_in=True, numDigits=1, speechModel="phone_call", enhanced="true", action=action_url,
                        language=tts_lang, timeout=TIMEOUT_OUTBOUND, speechTimeout=str(speech_to))
        gather.say(ai_next, voice=tts_voice, language=tts_lang)
        response.append(gather)
        response.say(get_msg("TIMEOUT_REPORT", lang).format(contact_name=contact_name), voice=tts_voice, language=tts_lang)
        response.hangup()
        # 통화 완전 종료 후 보고 (completed 콜백에서 처리)
        if call_sid in outbound_sessions:
            outbound_sessions[call_sid]["pending_summary"] = True
        print(f"📋 timeout 종료 대기 중 — completed 콜백 후 보고 예정: {contact_name}")

    return Response(str(response), mimetype="text/xml")


@app.route("/voice-report", methods=["POST"])
@validate_twilio_request
def voice_report():
    report_id = request.args.get("rid", "")
    report = _pending_reports.pop(report_id, None)
    msg = report["msg"] if report else "통화가 완료되었습니다."
    response = VoiceResponse()
    lang     = detect_lang(MY_PHONE)
    tts_lang = get_twilio_lang(lang)
    tts_voice = get_tts_voice(lang)
    tts_lang = get_twilio_lang(lang)
    tts_voice = get_tts_voice(lang)
    response.say(f"{get_msg('VOICE_REPORT_PREFIX', lang)}{msg}", voice=tts_voice, language=tts_lang)
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
@validate_twilio_request
def call_status():
    call_sid     = request.form.get("CallSid", "")
    call_status  = request.form.get("CallStatus", "")
    # 📞 수신전화(관리자 직접 전화) 통화시간을 월 누적에 기록
    _direction   = request.form.get("Direction", "")
    _duration    = request.form.get("CallDuration", "0")
    _from        = request.form.get("From", "")
    if call_status == "completed" and _direction.startswith("inbound"):
        try:
            if is_admin(_from):
                _record_inbound_call_seconds(_duration)
        except Exception as _e:
            print(f"⚠️ 수신전화 시간 기록 오류(무시): {_e}")

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

    # 통화 완전 종료 후 보고
    if call_status == "completed" and session:
        already_sent = session.get("summary_sent", False) or session.get("summary_scheduled", False)
        has_history  = len(session.get("history", [])) > 0
        pending      = session.get("pending_summary", False)

        if not already_sent:
            if pending:
                # 정상 종료
                print(f"✅ 통화 완전 종료 — 정상 보고: {name}")
                session["summary_scheduled"] = True
                threading.Timer(TIMER_SUMMARY_START, send_summary_to_admin, args=[call_sid]).start()
            elif has_history:
                # 대화 중 상대방 강제 종료 — force_hangup 플래그 설정
                print(f"⚠️ 상대방 강제 종료 — 대화 기록으로 보고: {name} ({len(session.get('history',[]))}턴)")
                session["force_hangup"] = True
                session["summary_scheduled"] = True
                threading.Timer(TIMER_SUMMARY_START, send_summary_to_admin, args=[call_sid]).start()
            else:
                # 대화 0턴 — 인사말도 못 하고 끊김
                print(f"⚠️ 통화 연결 후 즉시 종료 — 즉시 보고: {name}")
                session["summary_sent"] = True
                display_number = number.replace("+82", "0") if number.startswith("+82") else number
                report_inst_display = report_to.replace("+82", "0") if report_to.startswith("+82") else report_to
                report_inst_line = f"\n📩 보고대상: {report_inst_display}" if report_to != MY_PHONE else ""
                tg_instant_msg = f"⚠️ <b>[AI통화보고]</b>\n👤 대상: {name}님 ({display_number})\n📊 결과: 전화를 받은 직후 바로 끊었습니다.{report_inst_line}"
                # ① report_to 번호로 안내 SMS 발송
                guide_sms = f"[안내] {name}님({display_number})께 전화했으나 받자마자 끊으셨습니다. 직접 전화해서 다시 물어보세요."
                def send_instant_guide():
                    try:
                        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                        client.messages.create(to=report_to, from_=TWILIO_PHONE, body=guide_sms)
                        print(f"📱 즉시 끊김 → 안내 SMS 발송: {report_to}")
                    except Exception as e:
                        print(f"안내 SMS 오류: {e}")
                    # ② 관리자 Telegram 알림
                    send_to_telegram(tg_instant_msg)
                threading.Timer(5.0, send_instant_guide).start()
            return "", 204

    if call_status in status_map:
        reason = status_map[call_status]
        display_number = number.replace("+82", "0") if number.startswith("+82") else number
        print(f"📵 통화 실패: {name}({number}) - {call_status}")

        # Telegram 알림 메시지 준비
        report_fail_display = report_to.replace("+82", "0") if report_to.startswith("+82") else report_to
        report_fail_line = f"\n📩 보고대상: {report_fail_display}" if report_to != MY_PHONE else ""
        tg_fail_msg = f"🚨 <b>[AI통화보고]</b>\n👤 대상: {name}님 ({display_number})\n📊 결과: {reason}{report_fail_line}"

        # summary_sent 마킹 — 중복 보고 방지
        if call_sid in outbound_sessions:
            outbound_sessions[call_sid]["summary_sent"] = True

        # ① report_to 번호로 안내 SMS 발송
        guide_sms = f"[안내] {name}님({display_number})께 전화했으나 {reason}. 직접 전화해서 다시 물어보세요."
        def send_fail_guide():
            try:
                client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                client.messages.create(to=report_to, from_=TWILIO_PHONE, body=guide_sms)
                print(f"📱 통화 실패 → 안내 SMS 발송: {report_to}")
            except Exception as e:
                print(f"안내 SMS 오류: {e}")
            # ② 관리자 Telegram 알림
            send_to_telegram(tg_fail_msg)
        threading.Timer(TIMER_SMS_REPORT, send_fail_guide).start()

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
    # 보안: SMS 입력 길이 제한 + null byte 제거
    message_body = message_body.replace("\x00", "")
    if len(message_body) > 1600:
        message_body = message_body[:1600]
    
    print(f"📱 SMS 수신: {from_number} → {message_body[:100]}{'...' if len(message_body)>100 else ''}")
    
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
    
    # 관리자에게 SMS 전달 + Telegram 알림 (5초 후)
    tg_reply_name = sender_name or display_number
    tg_reply_msg = f"📩 <b>[SMS답장]</b>\n👤 발신: {tg_reply_name}\n💬 내용: {message_body[:200]}"
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
        # Telegram 알림 (SMS 전달과 동시)
        send_to_telegram(tg_reply_msg)
    
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
    to = data.get("to", "").strip()
    message = data.get("message", "").strip()
    
    if not to or not message:
        return jsonify({"error": "to, message 필수"}), 400

    # 보안: E.164 형식 검증 + 허용 국가 코드 제한 (프리미엄 번호 요금 폭탄 방지)
    import re
    if not re.match(r'^\+[1-9]\d{6,14}$', to):
        return jsonify({"error": "전화번호는 E.164 형식이어야 합니다 (예: +821012345678)"}), 400
    if not is_country_allowed(to):
        print(f"🚨 SMS 차단: 허용되지 않은 국가 코드 → {to[:4]}*** (요금폭탄 방지)")
        return jsonify({"error": f"허용되지 않은 국가 코드입니다. 허용: {', '.join(ALLOWED_COUNTRY_CODES)}"}), 403
    # 💰 하루 문자 한도 검사
    _sok, _sreason = can_send_sms()
    if not _sok:
        print(f"🚨 SMS 차단: {_sreason} (요금폭탄 방지)")
        return jsonify({"error": _sreason}), 429

    # 보안: SMS 본문 길이 제한
    if len(message) > 1600:
        message = message[:1600]
    
    try:
        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        msg = client.messages.create(
            to=to,
            from_=TWILIO_PHONE,
            body=message
        )
        
        # ✅ 성공 시 - 로그만 출력 (관리자 SMS 보고 없음)
        print(f"📱 SMS 발송 성공: {to} - {message}")
        _record_sms()  # 하루 문자 카운터 증가
        
        # Telegram 알림 (3초 후 발송)
        display_to = to.replace("+82", "0") if to.startswith("+82") else to
        contact_name = ""
        for cname, cnum in CONTACTS.items():
            if cnum == to:
                contact_name = cname
                break
        tg_name = f"{contact_name}님 ({display_to})" if contact_name else display_to
        tg_sms_msg = f"✅ <b>[SMS발송]</b>\n👤 대상: {tg_name}\n💬 내용: {message[:100]}"
        threading.Timer(3.0, lambda: send_to_telegram(tg_sms_msg)).start()
        
        return jsonify({
            "status": "sent",
            "sid": msg.sid,
            "to": to,
            "message": message
        })
        
    except Exception as e:
        # ❌ 실패 시 - 관리자에게 실패 보고
        print(f"📱 SMS 발송 실패: {to} - {str(e)}")
        
        display_number = to.replace("+82", "0") if to.startswith("+82") else to
        error_detail = str(e)[:50]
        failure_report = f"[SMS전송실패] {display_number}에게 문자 전송 실패.\n오류: {error_detail}"
        
        # Telegram 실패 알림 메시지 준비
        tg_fail = f"❌ <b>[SMS실패]</b>\n👤 대상: {display_number}\n⚠️ 오류: {error_detail}"
        
        def send_sms_failure_report_api():
            try:
                client_r = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                client_r.messages.create(
                    to=MY_PHONE,
                    from_=TWILIO_PHONE,
                    body=failure_report
                )
                print(f"📱 SMS 실패 보고 발송 ({TIMER_SMS_FAILURE}초 지연) → {MY_PHONE}: {failure_report}")
            except Exception as report_error:
                print(f"SMS 실패 보고 전송 오류: {report_error}")
            # Telegram 알림 (SMS 실패 보고와 동시)
            send_to_telegram(tg_fail)
        
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
    # 보안: 이름 길이 제한
    if len(name) > 30:
        return jsonify({"error": "이름은 30자 이내"}), 400
    # 보안: 전화번호 자동 변환 + E.164 검증
    import re
    number = number.replace("-", "").replace(" ", "")
    if number.startswith("010") or number.startswith("011"):
        number = "+82" + number[1:]
    if not re.match(r'^\+[1-9]\d{6,14}$', number):
        return jsonify({"error": "전화번호는 E.164 형식이어야 합니다 (예: +821012345678)"}), 400
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


# ════════════════════════════════════════════
# 📼 통화 녹음 시스템 (ON/OFF 토글)
# ════════════════════════════════════════════

@app.route("/recording-callback", methods=["POST"])
@validate_twilio_request
def recording_callback():
    """Twilio 녹음 완료 콜백 → MP3 다운로드 후 로컬 저장, Twilio에서 삭제"""
    if not ENABLE_CALL_RECORDING:
        return "", 204

    rec_sid  = request.form.get("RecordingSid", "")
    rec_url  = request.form.get("RecordingUrl", "")
    call_sid = request.form.get("CallSid", "")
    duration = request.form.get("RecordingDuration", "0")

    if not rec_url:
        print(f"⚠️ 녹음 콜백: RecordingUrl 없음 (CallSid={call_sid})")
        return "", 204

    # 🔒 SSRF 방어: Twilio 공식 도메인만 허용
    from urllib.parse import urlparse
    _parsed_rec_url = urlparse(rec_url)
    _allowed_rec_hosts = ["api.twilio.com", "media.twiliocdn.com"]
    if _parsed_rec_url.hostname not in _allowed_rec_hosts:
        print(f"🚨 SSRF 차단: 허용되지 않은 녹음 URL 도메인 ({_parsed_rec_url.hostname}) — {rec_url[:80]}")
        return "", 204

    # 세션에서 이름 찾기
    session = outbound_sessions.get(call_sid, {})
    contact_name = session.get("name", "unknown")
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    safe_name = re.sub(r'[^\w가-힣]', '_', contact_name)
    filename = f"{timestamp}_{safe_name}_{duration}s.mp3"
    filepath = os.path.join(RECORDINGS_DIR, filename)

    try:
        # Twilio에서 MP3 다운로드 (인증 필요)
        mp3_url = f"{rec_url}.mp3"
        resp = requests.get(mp3_url, auth=(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN), timeout=30)
        if resp.status_code == 200:
            with open(filepath, "wb") as f:
                f.write(resp.content)
            file_size_mb = len(resp.content) / (1024 * 1024)
            print(f"📼 녹음 저장 완료: {filename} ({duration}초, {file_size_mb:.1f}MB)")

            # Twilio 서버에서 녹음 삭제 (요금 절약)
            try:
                client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                client.recordings(rec_sid).delete()
                print(f"🗑️ Twilio 녹음 삭제: {rec_sid}")
            except Exception as e:
                print(f"⚠️ Twilio 녹음 삭제 실패 (무시): {e}")

            # Telegram 알림
            display_name = f"{contact_name}({session.get('number', '')})"
            send_to_telegram(f"📼 <b>[통화 녹음 저장]</b>\n👤 대상: {display_name}\n⏱️ 길이: {duration}초\n📁 파일: {filename}")

            # 세션에 녹음 파일명 저장 (PDF 보고서 연동용)
            if call_sid in outbound_sessions:
                outbound_sessions[call_sid]["recording_file"] = filename
        else:
            print(f"⚠️ 녹음 다운로드 실패: HTTP {resp.status_code}")
            # 다운로드 실패해도 Twilio에서 녹음 삭제 (요금 방지)
            try:
                client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                client.recordings(rec_sid).delete()
                print(f"🗑️ Twilio 녹음 삭제 (다운로드 실패): {rec_sid}")
            except Exception as e2:
                print(f"⚠️ Twilio 녹음 삭제 실패: {e2}")
    except Exception as e:
        print(f"⚠️ 녹음 저장 오류: {e}")
        # 예외 발생해도 Twilio에서 녹음 삭제 시도 (요금 방지)
        if rec_sid:
            try:
                client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                client.recordings(rec_sid).delete()
                print(f"🗑️ Twilio 녹음 삭제 (오류 복구): {rec_sid}")
            except Exception as e3:
                print(f"⚠️ Twilio 녹음 삭제 실패 (오류 복구): {e3}")

    return "", 204


@app.route("/recordings", methods=["GET"])
@require_api_secret
def list_recordings():
    """저장된 녹음 파일 목록"""
    files = []
    if os.path.exists(RECORDINGS_DIR):
        for fname in sorted(os.listdir(RECORDINGS_DIR), reverse=True):
            if fname.endswith(".mp3"):
                fpath = os.path.join(RECORDINGS_DIR, fname)
                files.append({
                    "filename": fname,
                    "size_mb": round(os.path.getsize(fpath) / (1024*1024), 2),
                    "created": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(os.path.getctime(fpath)))
                })
    return jsonify({"count": len(files), "recordings": files[:50], "enabled": ENABLE_CALL_RECORDING})


@app.route("/recordings/<filename>", methods=["GET"])
@require_api_secret
def download_recording(filename):
    """녹음 파일 다운로드"""
    import re as _re
    if not _re.match(r'^[\w가-힣._-]+\.mp3$', filename):
        return jsonify({"error": "잘못된 파일명"}), 400
    filepath = os.path.join(RECORDINGS_DIR, filename)
    if not os.path.exists(filepath):
        return jsonify({"error": "파일 없음"}), 404
    from flask import send_file
    return send_file(filepath, mimetype="audio/mpeg", as_attachment=True, download_name=filename)


# ════════════════════════════════════════════
# 📄 통화 보고서 PDF 자동 생성 (ON/OFF 토글)
# ════════════════════════════════════════════

def generate_call_report_pdf(call_sid):
    """통화 종료 후 PDF 보고서 자동 생성"""
    if not ENABLE_PDF_REPORT:
        return None

    session = outbound_sessions.get(call_sid, {})
    if not session:
        return None

    try:
        from fpdf import FPDF

        contact_name = session.get("name", "unknown")
        number = session.get("number", "")
        mission = session.get("mission", "")
        history = session.get("history", [])
        report_to = session.get("report_to", MY_PHONE)
        recording_file = session.get("recording_file", "")
        call_start = session.get("call_start_time")
        duration = int(time.time() - call_start) if call_start else 0

        timestamp = time.strftime("%Y%m%d_%H%M%S")
        safe_name = re.sub(r'[^\w가-힣]', '_', contact_name)
        filename = f"report_{timestamp}_{safe_name}.pdf"
        filepath = os.path.join(REPORTS_DIR, filename)

        # 한국어 지원 폰트 확인 (시스템 폰트 또는 기본 폰트)
        pdf = FPDF()
        pdf.add_page()

        # 한글 폰트 시도 (없으면 기본 폰트)
        font_set = False
        for font_path in ["/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
                          "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
            if os.path.exists(font_path):
                pdf.add_font("CustomFont", "", font_path, uni=True)
                pdf.set_font("CustomFont", size=11)
                font_set = True
                break
        if not font_set:
            pdf.set_font("Helvetica", size=11)

        # 제목
        pdf.set_font_size(18)
        pdf.cell(0, 12, text="AI Call Report", ln=True, align="C")
        pdf.ln(5)

        # 기본 정보
        pdf.set_font_size(11)
        display_number = number.replace("+82", "0") if number.startswith("+82") else number
        info_lines = [
            f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}",
            f"Contact: {contact_name} ({display_number})",
            f"Mission: {mission}",
            f"Duration: {duration // 60}min {duration % 60}sec",
            f"Turns: {len(history)}",
            f"Report To: {report_to}",
        ]
        if recording_file:
            info_lines.append(f"Recording: {recording_file}")

        for line in info_lines:
            pdf.cell(0, 7, text=line, ln=True)
        pdf.ln(5)

        # 구분선
        pdf.set_draw_color(100, 100, 100)
        pdf.line(10, pdf.get_y(), 200, pdf.get_y())
        pdf.ln(5)

        # 대화 내용
        pdf.set_font_size(13)
        pdf.cell(0, 10, text="Conversation Log", ln=True)
        pdf.set_font_size(10)
        pdf.ln(3)

        for i, h in enumerate(history, 1):
            ai_text = h.get("ai", "")
            user_text = h.get("user", "")
            pdf.set_text_color(0, 100, 200)
            pdf.multi_cell(0, 6, text=f"AI: {ai_text}")
            pdf.set_text_color(0, 0, 0)
            pdf.multi_cell(0, 6, text=f"{contact_name}: {user_text}")
            pdf.ln(2)

        # 요약 (있으면)
        summary = session.get("_pdf_summary", "")
        if summary:
            pdf.ln(5)
            pdf.set_draw_color(100, 100, 100)
            pdf.line(10, pdf.get_y(), 200, pdf.get_y())
            pdf.ln(5)
            pdf.set_font_size(13)
            pdf.cell(0, 10, text="AI Summary", ln=True)
            pdf.set_font_size(10)
            pdf.multi_cell(0, 6, text=summary)

        pdf.output(filepath)
        file_size_kb = os.path.getsize(filepath) / 1024
        print(f"📄 PDF 보고서 생성: {filename} ({file_size_kb:.0f}KB)")

        # Telegram 알림
        send_to_telegram(f"📄 <b>[PDF 보고서 생성]</b>\n👤 대상: {contact_name}\n📁 파일: {filename}")
        return filename

    except Exception as e:
        print(f"⚠️ PDF 보고서 생성 오류: {e}")
        return None


@app.route("/reports", methods=["GET"])
@require_api_secret
def list_reports():
    """저장된 PDF 보고서 목록"""
    files = []
    if os.path.exists(REPORTS_DIR):
        for fname in sorted(os.listdir(REPORTS_DIR), reverse=True):
            if fname.endswith(".pdf"):
                fpath = os.path.join(REPORTS_DIR, fname)
                files.append({
                    "filename": fname,
                    "size_kb": round(os.path.getsize(fpath) / 1024, 1),
                    "created": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(os.path.getctime(fpath)))
                })
    return jsonify({"count": len(files), "reports": files[:50], "enabled": ENABLE_PDF_REPORT})


@app.route("/reports/<filename>", methods=["GET"])
@require_api_secret
def download_report(filename):
    """PDF 보고서 다운로드"""
    import re as _re
    if not _re.match(r'^[\w가-힣._-]+\.pdf$', filename):
        return jsonify({"error": "잘못된 파일명"}), 400
    filepath = os.path.join(REPORTS_DIR, filename)
    if not os.path.exists(filepath):
        return jsonify({"error": "파일 없음"}), 404
    from flask import send_file
    return send_file(filepath, mimetype="application/pdf", as_attachment=True, download_name=filename)


# ════════════════════════════════════════════
# 🔧 기능 토글 API (녹음/PDF ON↔OFF 실시간 전환)
# ════════════════════════════════════════════

@app.route("/toggle/recording", methods=["POST"])
@require_api_secret
def toggle_recording():
    """통화 녹음 ON/OFF 토글"""
    global ENABLE_CALL_RECORDING
    ENABLE_CALL_RECORDING = not ENABLE_CALL_RECORDING
    status = "활성화" if ENABLE_CALL_RECORDING else "비활성화"
    print(f"📼 통화 녹음 → {status}")
    send_to_telegram(f"📼 <b>통화 녹음 {'활성화 ✅' if ENABLE_CALL_RECORDING else '비활성화 ⭐'}</b>")
    return jsonify({"feature": "call_recording", "enabled": ENABLE_CALL_RECORDING, "status": status})


@app.route("/toggle/pdf-report", methods=["POST"])
@require_api_secret
def toggle_pdf_report():
    """PDF 보고서 ON/OFF 토글"""
    global ENABLE_PDF_REPORT
    ENABLE_PDF_REPORT = not ENABLE_PDF_REPORT
    status = "활성화" if ENABLE_PDF_REPORT else "비활성화"
    print(f"📄 PDF 보고서 → {status}")
    send_to_telegram(f"📄 <b>PDF 보고서 {'활성화 ✅' if ENABLE_PDF_REPORT else '비활성화 ⭐'}</b>")
    return jsonify({"feature": "pdf_report", "enabled": ENABLE_PDF_REPORT, "status": status})


@app.route("/toggle/status", methods=["GET"])
@require_api_secret
def toggle_status():
    """모든 토글 기능 상태 조회"""
    rec_count = len([f for f in os.listdir(RECORDINGS_DIR) if f.endswith(".mp3")]) if os.path.exists(RECORDINGS_DIR) else 0
    pdf_count = len([f for f in os.listdir(REPORTS_DIR) if f.endswith(".pdf")]) if os.path.exists(REPORTS_DIR) else 0
    return jsonify({
        "call_recording": {"enabled": ENABLE_CALL_RECORDING, "files": rec_count},
        "pdf_report":     {"enabled": ENABLE_PDF_REPORT, "files": pdf_count},
    })


# ═══════════════════════════════════════════════════════════════
# 🔟 실시간 귓속말 HTTP API (OpenWebUI 도구 / 앱에서 호출)
# ═══════════════════════════════════════════════════════════════
# ── 실시간 통화 서버(realtime-voice)가 호출하는 내부 엔드포인트 ──────────
# ── 🧠 기억의 앵커: realtime-voice / 도구가 호출하는 HTTP API ──────────
@app.route("/memory/save", methods=["POST"])
@require_api_secret
def api_memory_save():
    """통화 대화를 임베딩 저장 (realtime-voice 등이 통화 종료 시 호출)."""
    data = request.get_json() or {}
    ok = save_call_memory(
        phone_number=(data.get("phone_number") or "").strip(),
        name=(data.get("name") or "").strip(),
        conversation_text=(data.get("text") or ""),
        extra_summary=(data.get("summary") or ""),
    )
    return jsonify({"status": "saved" if ok else "skipped"})

@app.route("/memory/recall", methods=["POST"])
@require_api_secret
def api_memory_recall():
    """현재 조건과 비슷한 과거 기억을 프롬프트 조각으로 반환 (회상)."""
    data = request.get_json() or {}
    prompt = build_memory_prompt(
        phone_number=(data.get("phone_number") or "").strip(),
        name=(data.get("name") or "").strip(),
        query_text=(data.get("query") or ""),
    )
    mems = recall_memories(
        (data.get("phone_number") or "").strip(),
        (data.get("name") or "").strip(),
        (data.get("query") or ""),
    )
    return jsonify({"prompt": prompt, "memories": mems})


@app.route("/whisper/register", methods=["POST"])
@require_api_secret
def api_whisper_register():
    """realtime-voice 가 통화 시작 시 진행 목록에 등록."""
    data = request.get_json() or {}
    sid = (data.get("call_sid") or "").strip()
    if not sid:
        return jsonify({"error": "call_sid 필요"}), 400
    register_active_call(sid, name=data.get("name", "상대방"),
                         number=data.get("number", ""),
                         direction=data.get("direction", "inbound"))
    return jsonify({"status": "registered", "call_sid": sid})

@app.route("/whisper/unregister", methods=["POST"])
@require_api_secret
def api_whisper_unregister():
    """realtime-voice 가 통화 종료 시 정리."""
    data = request.get_json() or {}
    sid = (data.get("call_sid") or "").strip()
    unregister_active_call(sid)
    return jsonify({"status": "unregistered", "call_sid": sid})

@app.route("/whisper/pop", methods=["POST"])
@require_api_secret
def api_whisper_pop():
    """realtime-voice 가 매 발화 턴에 대기 중인 관리자 지시를 꺼내간다.
       (pop_whispers 는 프롬프트 틀로 감싸므로, 여기서는 원문만 반환)"""
    data = request.get_json() or {}
    sid = (data.get("call_sid") or "").strip()
    if not sid:
        return jsonify({"instruction": ""})
    with _whisper_lock:
        items = _whisper_queue.get(sid, [])
        if not items:
            return jsonify({"instruction": ""})
        combined = " / ".join(items)
        _whisper_queue[sid] = []
        _save_whispers()
    print(f"🎯 [realtime] 귓속말 pop [{sid}]: {combined[:60]}")
    return jsonify({"instruction": combined})


# ── 실시간 음성엔진(STT/TTS) 설정 저장/조회 — 밸브에서 런타임 교체 ──────────
#   realtime-voice 컨테이너가 같은 볼륨의 이 파일을 읽어 제공자/키/음성을 결정.
VOICE_CONFIG_FILE = "/app/data/voice_config.json"

@app.route("/voice-config", methods=["GET"])
@require_api_secret
def api_voice_config_get():
    """현재 저장된 음성엔진 설정 조회 (키는 마스킹)."""
    try:
        if os.path.exists(VOICE_CONFIG_FILE):
            with open(VOICE_CONFIG_FILE, "r", encoding="utf-8") as f:
                cfg = json.load(f)
        else:
            cfg = {}
    except Exception:
        cfg = {}
    masked = dict(cfg)
    for k in ("stt_api_key", "tts_api_key"):
        v = masked.get(k, "")
        if v:
            masked[k] = v[:4] + "***" + v[-2:] if len(v) > 6 else "***"
    return jsonify({"config": masked})

@app.route("/voice-config", methods=["POST"])
@require_api_secret
def api_voice_config_set():
    """밸브에서 넘어온 STT/TTS 설정을 파일에 저장 (다음 통화부터 적용).
       빈 값은 기존 값을 유지(덮어쓰지 않음)."""
    data = request.get_json() or {}
    try:
        cur = {}
        if os.path.exists(VOICE_CONFIG_FILE):
            with open(VOICE_CONFIG_FILE, "r", encoding="utf-8") as f:
                cur = json.load(f)
        allowed = ("stt_provider", "stt_api_key", "stt_model",
                   "tts_provider", "tts_api_key", "tts_voice", "tts_model",
                   "language", "system_prompt")
        for k in allowed:
            if k in data and str(data[k]).strip() != "":
                cur[k] = data[k]
        os.makedirs(os.path.dirname(VOICE_CONFIG_FILE), exist_ok=True)
        with open(VOICE_CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cur, f, ensure_ascii=False)
        return jsonify({"status": "saved", "applied_fields": [k for k in allowed if k in data and str(data[k]).strip() != ""]})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/whisper/active-calls", methods=["GET"])
@require_api_secret
def api_whisper_active_calls():
    """진행 중 통화 목록 반환 (앱/도구가 대상 선택용으로 조회)"""
    return jsonify({"calls": list_active_calls()})

@app.route("/whisper/send", methods=["POST"])
@require_api_secret
def api_whisper_send():
    """실시간 귓속말 지시 전달.
       body: {"instruction": "...", "target": "이름/번호/call_sid (선택)"}"""
    data = request.get_json() or {}
    instruction = (data.get("instruction") or "").strip()
    target = (data.get("target") or "").strip()
    if not instruction:
        return jsonify({"error": "instruction(전할 내용)이 비어 있습니다."}), 400

    call_sid, calls = _resolve_whisper_target(target)
    if not calls:
        return jsonify({"status": "no_active_call", "message": "진행 중인 통화가 없습니다."}), 200
    if call_sid is None:
        return jsonify({
            "status": "ambiguous",
            "message": "진행 중 통화가 여러 개입니다. target에 이름/번호를 지정하세요.",
            "candidates": [{"name": c["name"], "number": c["number"], "call_sid": c["call_sid"]} for c in calls],
        }), 200

    add_whisper(call_sid, instruction)
    tgt = next((c for c in calls if c["call_sid"] == call_sid), {})
    return jsonify({
        "status": "queued",
        "target": tgt.get("name", "상대방"),
        "call_sid": call_sid,
        "instruction": instruction,
        "message": f"{tgt.get('name','상대방')}님과의 통화에 지시를 전달했습니다. 다음 발화에 반영됩니다.",
    })

@app.route("/whisper/clear", methods=["POST"])
@require_api_secret
def api_whisper_clear():
    """특정 통화의 대기 중 귓속말 지시 취소.
       body: {"target": "이름/번호/call_sid (선택)"}"""
    data = request.get_json() or {}
    target = (data.get("target") or "").strip()
    call_sid, calls = _resolve_whisper_target(target)
    if not calls:
        return jsonify({"status": "no_active_call", "message": "진행 중인 통화가 없습니다."}), 200
    if call_sid is None:
        return jsonify({"status": "ambiguous", "message": "대상을 지정하세요.",
                        "candidates": [{"name": c["name"], "call_sid": c["call_sid"]} for c in calls]}), 200
    with _whisper_lock:
        cnt = len(_whisper_queue.get(call_sid, []))
        _whisper_queue[call_sid] = []
        _save_whispers()
    return jsonify({"status": "cleared", "call_sid": call_sid, "removed": cnt})


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


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
        # 🔒 루프백(로컬)에서만 허용 — 통화 기록은 민감 데이터이므로 사설망 전체가 아닌
        #    127.0.0.1/::1 로만 제한 (대시보드는 로컬 브라우저에서 호출됨).
        remote = request.remote_addr or ""
        if remote not in ("127.0.0.1", "::1", "localhost"):
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
        report_to = s.get("report_to", "") or MY_PHONE

        # 📅 캘린더 일정 알림(셀프 리마인더): 관리자 본인에게 거는 알림.
        #    contact_name 이 __self_reminder__ 이면 CONTACTS 조회 없이 MY_PHONE 으로 바로 발송.
        if contact_name == "__self_reminder__":
            if not MY_PHONE:
                print("❌ 일정 알림 실패: 관리자 전화번호(MY_PHONE) 미설정")
                return
            # 🗑️ 발송 직전 확인: 캘린더에서 삭제된 일정이면 알림 안 보냄
            _ct = s.get("cal_title")
            _cs = s.get("cal_start")
            if _ct is not None and _cs is not None:
                try:
                    if not _calendar_event_exists(_ct, _cs):
                        print(f"🗑️ 일정 알림 취소: 캘린더에서 삭제된 일정 ('{_ct}') — 전화·문자 안 보냄")
                        return
                except Exception:
                    pass
            if action == "call":
                sid = make_call(MY_PHONE, message or "예정된 일정 알림입니다.")
                print(f"📞 일정 알림 전화: 관리자 ({MY_PHONE})" if sid else "❌ 일정 알림 전화 실패")
            elif action == "sms":
                try:
                    Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN).messages.create(
                        to=MY_PHONE, from_=TWILIO_PHONE,
                        body=message or "예정된 일정 알림입니다.")
                    print(f"📱 일정 알림 SMS: 관리자 ({MY_PHONE})")
                except Exception as e:
                    print(f"❌ 일정 알림 SMS 실패: {e}")
            return

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
                report_to=report_to
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

    # 🧠 기억의 앵커 능동형 자동전화 감시 스레드 시작 (기본 OFF)
    try:
        threading.Thread(target=_memory_autocall_loop, daemon=True).start()
    except Exception as _e:
        print(f"⚠️ 자동전화 스레드 시작 실패(무시): {_e}")

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
            enabled=data.get("enabled", True),
            report_to=data.get("report_to", "")
        )
        return jsonify({"status": "added", "sid": sid, "schedule": scheduler.schedules[sid]})

    @app.route("/calendar-reminder", methods=["POST"])
    @require_api_secret
    def calendar_reminder():
        """캘린더 일정 알림 예약 (챗/텔레그램 tool 이 호출).
        일정 시작 (reminder_min)분 전에 관리자에게 전화+SMS 를 1회 예약한다.
        body: {"title": "...", "start_epoch": 1234567890, "reminder_min": 30}
        수정 시: old_title 을 함께 주면 그 제목의 옛 알림을 먼저 취소한다.
        삭제 시: {"cancel_only": true, "title": "..."} 로 알림만 취소 가능."""
        data = request.get_json() or {}
        title = (data.get("title") or "일정").strip()

        # 옛 제목의 알림 취소 (제목이 바뀌는 수정)
        old_title = (data.get("old_title") or "").strip()
        if old_title and old_title != title:
            try:
                _rm = scheduler.remove_calendar_reminders(old_title)
                if _rm:
                    print(f"🔄 옛 제목 알림 {_rm}건 취소 ('{old_title}')")
            except Exception:
                pass

        # 알림만 취소 (일정 삭제 시)
        if data.get("cancel_only"):
            try:
                n = scheduler.remove_calendar_reminders(title)
                return jsonify({"status": "cancelled", "removed": n, "title": title})
            except Exception as e:
                return jsonify({"status": "error", "reason": str(e)}), 500

        try:
            start_epoch = int(data.get("start_epoch", 0))
            reminder_min = int(data.get("reminder_min", 0))
        except (TypeError, ValueError):
            return jsonify({"status": "error", "reason": "start_epoch/reminder_min 형식 오류"}), 400
        if reminder_min <= 0 or start_epoch <= 0:
            # 알림값이 없으면, 혹시 남아있는 옛 알림만 정리하고 종료
            try:
                scheduler.remove_calendar_reminders(title)
            except Exception:
                pass
            return jsonify({"status": "skipped", "reason": "알림 없음 또는 시작시각 없음"})
        ok = _schedule_event_reminder(title, start_epoch, reminder_min)
        if ok:
            return jsonify({"status": "scheduled", "title": title, "reminder_min": reminder_min})
        return jsonify({"status": "skipped", "reason": "알림 시각이 지났거나 관리자 번호 미설정"})

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
# 수정 후: cd ~/OpenWebUI && docker compose restart twilio-bot
# ═══════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════
# ⭐ 0-A. 서비스 모드 (고객전용 ↔ 개인용 전환) — 이 한 줄만 바꾸면 됩니다!
# ═══════════════════════════════════════════════════════════
# 이 파일 하나로 "고객 상담용" 과 "개인용(지인 안부/대리전화)" 을 전환합니다.
# 아래 SERVICE_MODE 값만 바꾸고 저장한 뒤:
#     cd ~/OpenWebUI && docker compose restart twilio-bot
#
#   SERVICE_MODE = "customer"  → 고객 상담 모드 (기본값)
#       · 걸려온 전화를 '고객 상담'으로 응대 (상담원 0번 연결 안내 ON)
#       · 인사말이 상담체("무엇을 도와드릴까요?")
#       · 능동형 자동전화 OFF (고객에게 먼저 전화 거는 기능 꺼짐)
#
#   SERVICE_MODE = "personal"  → 개인용 모드
#       · 걸려온 전화를 '지인 안부'로 따뜻하게 응대
#       · 인사말이 안부체("잘 지내고 계시죠?")
#       · 상담원 0번 안내 멘트 OFF (개인용은 굳이 안내 안 함)
#       · 관리자 명령(연락처 저장·안부전화·문자·예약) 그대로 사용
#       · 기억의 앵커 능동형 자동전화를 켤 수 있음(아래 MEMORY_AUTOCALL_* 조절)
#
# ※ 세부 항목(상담원 연결·인사말·자동전화 등)은 이 파일 아래쪽 각 설정에서
#   개별적으로 다시 미세조정할 수 있습니다. SERVICE_MODE 는 그 "기본 묶음"을
#   한 번에 바꿔주는 스위치입니다.
# ※ 파일 맨 끝의 "모드 적용 로직"이 이 값을 읽어 관련 설정을 자동 조정합니다.
SERVICE_MODE = "customer"   # "customer"(고객전용) 또는 "personal"(개인용)

# ─── 0. 기본 언어 설정 ────────────────────────────────
# 자동 감지 실패 시 사용할 기본 언어
DEFAULT_LANG = "ko"  # "ko", "en", "ja", "zh"

# ─── 0-B. 끼어들기(barge-in) 설정 ─────────────────────
# 통화 중 AI가 말하는 도중 상대방이 끼어들었을 때의 동작을 조절합니다.
#
# BARGEIN_THRESHOLD: 끼어들기로 판단하는 민감도 (0.0 ~ 1.0)
#   - AI 답변의 예상 낭독 시간 중 "이 비율 이전"에 상대방이 말하면 끼어들기로 봅니다.
#   - 값이 클수록 민감 (조금만 빨리 말해도 끼어들기로 인식)
#   - 값이 작을수록 둔감 (확실히 일찍 말해야 끼어들기로 인식)
#   - 0.6 = 답변의 60% 이전에 말하면 끼어들기 (권장 기본값)
BARGEIN_THRESHOLD = 0.6

# BARGEIN_MIN_SECONDS: 이 시간(초)보다 짧은 답변은 끼어들기 판단에서 제외
#   - 짧은 답변("네", "알겠습니다")은 끼어들 일이 거의 없으므로 무시
BARGEIN_MIN_SECONDS = 3.0

# BARGEIN_ENABLED: 끼어들기 맥락 처리 자체를 켜고 끔
BARGEIN_ENABLED = True

# BARGEIN_CPS: 언어별 TTS 실측 낭독 속도(초당 글자수). 목소리가 빠르면 올리고 느리면 내림.
BARGEIN_CPS = {"ko": 4.5, "en": 14.0, "ja": 5.5, "zh": 4.0}
# BARGEIN_CONF_HINT: 음성인식 신뢰도 보조 판단 임계값(0~1). 오탐 많으면 낮추고, 더 잘 잡으려면 올림.
BARGEIN_CONF_HINT = 0.55

# ─────────────────────────────────────────────────────
# 🎤 음성 인식 대기시간 (말이 끝났다고 판단하기까지 기다리는 시간)
# ─────────────────────────────────────────────────────
# 값이 클수록: 말 중간에 잠깐 멈추거나 생각해도 봇이 성급하게 끊지 않음 (여유롭게 말 가능)
# 값이 작거나 "auto": 말을 멈추면 즉시 반응 (빠르지만 성급할 수 있음)
# 숫자는 "초" 단위 문자열로 지정. (예: "3" = 3초 기다림)
#
# SPEECH_TIMEOUT_ADMIN: 관리자 통화(일정 등록 등 긴 명령). 넉넉하게 권장.
SPEECH_TIMEOUT_ADMIN    = "2"
# SPEECH_TIMEOUT_INBOUND: 걸려온 전화 응대.
SPEECH_TIMEOUT_INBOUND  = "3"
# SPEECH_TIMEOUT_OUTBOUND: 봇이 거는 안부전화.
SPEECH_TIMEOUT_OUTBOUND = "3"

# ─────────────────────────────────────────────────────
# 💬 전화 AI 답변 길이 (max_tokens)
# ─────────────────────────────────────────────────────
# 전화 통화에서 AI가 한 번에 답하는 최대 길이. 짧을수록 답변 생성·낭독이 빨라집니다.
#   - 100: 가장 짧고 빠름 (대략 1~2문장) — 통화용 권장
#   - 150: 적당 (2~3문장)
#   - 200: 좀 더 여유 (설명이 자주 필요하면)
# 답변이 너무 짧게 잘려 어색하면 값을 올리고, 더 빠르게 하려면 내리세요.
AI_MAX_TOKENS_CALL = 100

# ─────────────────────────────────────────────────────
# 🧠 전화 봇 AI 모델 선택 (CALL_MODEL)
# ─────────────────────────────────────────────────────
# 전화 통화에 사용할 AI 모델을 지정합니다.
#   - 빈 문자열 "" 로 두면 .env 의 OPENAI_MODEL(기본 llama-3.3-70b-versatile)을 그대로 사용
#   - 모델 이름을 넣으면 그 모델로 전화 통화를 처리
# 사용 가능한 모델은 Groq(BOT_MODE=2) 기준 예시:
#   - "llama-3.3-70b-versatile"  : 빠름. 일반 통화·대화에 적합. 가끔 한글이 살짝 깨질 수 있음
#   - "openai/gpt-oss-120b"      : 한글 처리 정확. 일정 등록·이름 등 정확도 중요할 때. 약간 느릴 수 있음
#   - "llama-3.1-8b-instant"     : 매우 빠름. 품질은 낮음
# ⚠️ 반드시 Groq에서 제공하는 정확한 모델 이름을 넣어야 합니다(오타 시 통화 실패).
#    한글이 자주 깨지면 "openai/gpt-oss-120b" 로, 속도가 중요하면 llama-3.3 로 두세요.
CALL_MODEL = ""

# BARGEIN_NOTE: 끼어들기 감지 시 AI에게 주는 지시문 (말투/행동 조절)
BARGEIN_NOTE = (
    "[상황: 사용자가 당신의 이전 답변 도중에 끼어들어 새로 말했습니다. "
    "이전 답변을 계속 이어가지 말고, 먼저 '네', '아 그러셨군요' 같은 짧은 맞장구로 "
    "받아준 뒤, 아래 사용자의 새 말에 정확히 집중해서 답하세요.]"
)

# ─── 0-B2. 관리자 명령 PIN 인증 설정 ─────────────────
# 관리자 번호로 전화했을 때, '민감 명령'(연락처 저장·전화 걸기·문자 보내기·예약)을
# 실행하려는 순간에만 PIN을 한 번 확인합니다. 통화당 1회 인증하면 그 통화 내내 유효합니다.
# 일반 대화나 '오늘 일정' 같은 조회에는 PIN을 묻지 않습니다.
# 지인·고객(미등록 번호)은 애초에 명령 권한이 없으므로 PIN과 무관합니다.
#
# ADMIN_PIN_REQUIRED: True 면 민감 명령 실행 전 PIN 확인, False 면 예전처럼 번호만으로 실행
ADMIN_PIN_REQUIRED = True
#
# 민감 명령으로 볼 키워드를 바꾸고 싶으면 아래 목록을 조정하세요(비워두면 기본값 사용).
# SENSITIVE_CMD_KEYWORDS = ["전화해줘", "문자", "저장해줘", "예약해줘", ...]

# ─── 0-C. 상담원(0번) 직통 연결 안내 설정 ──────────────
# 통화 중 0번을 누르면 관리자에게 직통 연결됩니다.
#
# OPERATOR_TRANSFER_ENABLED: 0번 직통 연결 "기능 자체"를 켜고 끔
#   - True:  0번을 누르면 관리자에게 연결됨 (권장: 고객 상담용)
#   - False: 0번을 눌러도 연결 안 됨 (기능 완전히 끔)
OPERATOR_TRANSFER_ENABLED = True

# OPERATOR_HINT_ENABLED: 통화 시작 시 "0번을 눌러주세요" 안내 멘트를 켜고 끔
#   - True:  인사 직후 0번 안내 멘트를 들려줌
#   - False: 안내 멘트 없음
#   ※ OPERATOR_TRANSFER_ENABLED=False 이면 이 값과 무관하게 안내도 안 나감
# ※ 멘트 내용은 아래 MESSAGES의 "OPERATOR_HINT" 에서 언어별로 수정 가능
OPERATOR_HINT_ENABLED = True

# OPERATOR_VOICE_ENABLED: 음성으로 "담당자 바꿔줘" 라고 말하면 연결되는 기능을 켜고 끔
#   - True:  아래 OPERATOR_VOICE_KEYWORDS 중 하나를 말하면 관리자에게 연결됨
#   - False: 음성으로 요청해도 연결 안 됨 (0번 키패드 기능과는 별개)
OPERATOR_VOICE_ENABLED = True

# OPERATOR_VOICE_KEYWORDS: 음성 담당자 연결을 발동시키는 키워드 목록
#   - 이 중 하나라도 통화 음성에 포함되면 관리자에게 연결됩니다.
#   - 원하는 표현을 자유롭게 추가/삭제하세요.
OPERATOR_VOICE_KEYWORDS = [
    "담당자", "사람이랑", "직접 연결", "관리자 바꿔", "사람 바꿔",
    "transfer", "connect me", "real person", "manager",
    "担当者", "人に繋いで", "转接", "找人",
]

# ═══════════════════════════════════════════════════════════
# 🧠 기억의 앵커 — 능동형 자동전화 설정 (반응형 ↔ 능동형 전환)
# ═══════════════════════════════════════════════════════════
# MEMORY_AUTOCALL_ENABLED: 능동형 자동전화 "기능 자체"의 마스터 스위치
#   - False: 반응형만 (전화 오거나 관리자가 시킬 때만 기억 활용) ← 기본값(안전)
#   - True:  능동형 켬 (조건이 맞으면 시스템이 먼저 안부전화 제안/발신)
MEMORY_AUTOCALL_ENABLED = False

# MEMORY_AUTOCALL_MODE: 켰을 때 동작 방식
#   - "suggest": 조건 맞으면 관리자에게 먼저 알림 → 관리자가 승인하면 발신 (안전, 추천)
#   - "auto":    조건 맞으면 곧바로 자동 발신 (주의: 요금·빈도 관리 필요)
MEMORY_AUTOCALL_MODE = "suggest"

# MEMORY_AUTOCALL_HOURS: 자동전화(또는 제안)를 허용할 시간대 [시작시, 종료시]
#   예) [10, 20] = 오전 10시 ~ 오후 8시 사이에만. 새벽 발신 방지.
MEMORY_AUTOCALL_HOURS = [10, 20]

# MEMORY_AUTOCALL_COOLDOWN_DAYS: 같은 사람에게 다시 자동전화하기까지 최소 간격(일)
#   예) 7 = 한 사람당 최소 7일에 한 번만. 스토킹처럼 자주 거는 것 방지.
MEMORY_AUTOCALL_COOLDOWN_DAYS = 7

# MEMORY_AUTOCALL_MATCH: 어떤 조건이 맞아야 "지금이 그때와 비슷하다"고 볼지
#   가능한 값: "time_slot"(시간대), "weather"(날씨)
#   예) ["time_slot", "weather"] = 시간대 AND 날씨가 모두 과거와 같아야 발동
#       ["time_slot"] = 시간대만 맞으면 발동 (더 자주 걸림)
MEMORY_AUTOCALL_MATCH = ["time_slot", "weather"]

# MEMORY_AUTOCALL_CHECK_INTERVAL_MIN: 조건을 확인하는 주기(분). 기본 30분.
MEMORY_AUTOCALL_CHECK_INTERVAL_MIN = 30

# MEMORY_AUTOCALL_MAX_PER_DAY: 하루 전체 자동전화(제안 포함) 최대 횟수 (요금·과다 방지)
MEMORY_AUTOCALL_MAX_PER_DAY = 3

# MEMORY_AUTOCALL_MISSION: 자동 안부전화 시 AI에게 주는 임무(대화 목적)
MEMORY_AUTOCALL_MISSION = "예전 대화를 떠올리며 자연스럽게 안부를 묻고 근황을 확인"

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

# Twilio Neural TTS 음성 (고품질 — 더 자연스러운 발음)
TWILIO_TTS_VOICE = {
    "ko": "Polly.Seoyeon-Neural",       # 한국어 - Amazon Neural (최고 품질)
    "en": "Polly.Joanna-Neural",         # 영어 - Amazon Neural
    "ja": "Google.ja-JP-Neural2-B",      # 일본어 - Google Neural
    "zh": "Google.cmn-CN-Wavenet-A",     # 중국어 - Google WaveNet
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

def get_tts_voice(lang_key):
    """언어 키를 Twilio Neural TTS 음성으로 변환"""
    return TWILIO_TTS_VOICE.get(lang_key, TWILIO_TTS_VOICE[DEFAULT_LANG])

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
        "개인정보 보호: 관리자나 다른 사람의 전화번호·주소·개인정보를 절대 알려주지 마세요. "
        "번호나 개인정보를 물으면 '죄송하지만 개인정보는 알려드릴 수 없습니다'라고 정중히 거절하세요. "
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
        "PIN_RETRY":          "PIN이 일치하지 않습니다. 다시 입력한 뒤 우물 정 자를 눌러 주세요.",
        "PIN_OK":             "인증되었습니다. 무엇을 도와드릴까요?",
        "TRANSFER":           "네, 담당자에게 바로 연결해 드릴게요. 잠시만요!",
        "OPERATOR_HINT":      "상담원 연결을 원하시면 0번을 눌러주세요.",
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
        "NOT_ADMIN":          "죄송합니다. 등록된 관리자 번호만 이용하실 수 있습니다.",
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
        "PIN_RETRY":          "That PIN did not match. Please enter it again, then press the pound key.",
        "PIN_OK":             "Verified. How can I help you?",
        "TRANSFER":           "Sure, let me connect you to the person in charge right away!",
        "OPERATOR_HINT":      "To reach a representative, press zero.",
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
        "NOT_ADMIN":          "Sorry, only registered admin numbers can use this service.",
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
        "PIN_RETRY":          "PINが一致しません。もう一度入力し、シャープを押してください。",
        "PIN_OK":             "認証されました。ご用件をどうぞ。",
        "TRANSFER":           "はい、担当者にすぐお繋ぎしますね。少々お待ちください！",
        "OPERATOR_HINT":      "担当者におつなぎする場合は、ゼロを押してください。",
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
        "NOT_ADMIN":          "申し訳ございません。登録された管理者番号のみご利用いただけます。",
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
        "PIN_RETRY":          "PIN码不匹配。请重新输入，然后按井号键。",
        "PIN_OK":             "验证成功。请问需要什么帮助？",
        "TRANSFER":           "好的，马上为您转接负责人。请稍等！",
        "OPERATOR_HINT":      "需要人工服务请按零。",
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
        "NOT_ADMIN":          "抱歉，仅限已注册的管理员号码使用。",
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
TIMEOUT_INBOUND = 4
TIMEOUT_OUTBOUND = 5          # 🔧 무응답 5초 후 통화 종료
SLOW_DOWN_MAX = 3             # 🔧 2→3회: 천천히 요청 최대 횟수 증가
SLOW_DOWN_MIN_CHARS = 2       # 🔧 3→2자: 더 짧은 음성도 감지

# ─── 7-B. 💰 요금 폭탄 방지 설정 ──────────────────────
# 통화·문자 요금이 예상치 못하게 폭증하는 것을 막는 안전장치입니다.
#
# CALL_TIME_LIMIT_SEC: 봇이 거는 통화 1건의 최대 길이(초). 이 시간이 지나면
#   Twilio가 통화를 강제 종료합니다. 통화가 무한정 이어져 요금이 늘어나는 것을 방지.
#   (예: 240 = 4분, 180 = 3분). 너무 짧으면 정상 대화가 중간에 끊길 수 있습니다.
CALL_TIME_LIMIT_SEC = 240

# ALLOWED_COUNTRY_CODES: 봇이 전화·문자를 보낼 수 있는 국가 코드 허용 목록.
#   여기 없는 국가 코드로는 발신이 차단됩니다. 프리미엄·국제 번호로 인한
#   요금 폭탄을 막는 핵심 장치입니다. 필요한 국가만 남기세요.
#   (+82 한국, +1 미국/캐나다, +81 일본, +86 중국, +44 영국, +49 독일, +33 프랑스, +61 호주)
ALLOWED_COUNTRY_CODES = ["+82", "+1", "+81", "+86", "+44", "+49", "+33", "+61"]

# MAX_OUTBOUND_CALLS_PER_DAY: 하루에 봇이 걸 수 있는 최대 통화 수.
#   이 횟수를 넘으면 그날은 더 이상 전화를 걸지 않습니다(자정에 초기화).
#   오작동·반복 명령으로 인한 대량 발신 요금을 방지. 0 이면 무제한.
MAX_OUTBOUND_CALLS_PER_DAY = 30

# MAX_SMS_PER_DAY: 하루에 봇이 보낼 수 있는 최대 문자 수. 0 이면 무제한.
MAX_SMS_PER_DAY = 50

# ─── 📞 관리자 수신전화(직접 전화) 월 통화시간 제한 ────────────────
# 관리자가 Twilio 번호로 "직접 전화를 걸어" 사용하는 통화의 월 누적 시간을 제한합니다.
# (봇이 거는 발신전화가 아니라, 관리자가 Twilio에 거는 수신전화 기준)
#
# MONTHLY_INBOUND_CALL_LIMIT_MIN: 월 최대 통화 시간(분). 이 시간을 넘으면 전화가 차단됩니다.
#   매달 21일에 자동으로 초기화됩니다. 0 이면 무제한.
MONTHLY_INBOUND_CALL_LIMIT_MIN = 300

# MONTHLY_CALL_WARN_PERCENT: 이 비율(%) 이상 사용하면 텔레그램으로 경고를 1회 보냅니다.
#   예: 90 이면 270분(300분의 90%) 사용 시 경고. 0 이면 경고 없음.
MONTHLY_CALL_WARN_PERCENT = 90

# MONTHLY_CALL_LIMIT_ENABLED: 월 통화시간 제한 기능 on/off.
MONTHLY_CALL_LIMIT_ENABLED = True


# ─── 7-1. 음성 인식 설정 ─────────────────────────────
# speechTimeout: 사용자가 말을 멈춘 뒤 "말이 끝났다"고 판단하기까지 기다리는 시간.
#   "auto" = Twilio가 즉시 자동 감지 (빠르지만, 생각하며 멈추면 성급하게 끊김)
#   숫자(초) = 그 시간만큼 더 기다림 (여유롭게 말할 수 있음)
# ai_config.py 의 SPEECH_TIMEOUT_INBOUND / SPEECH_TIMEOUT_OUTBOUND 로 조절 가능.
SPEECH_TIMEOUT_INBOUND  = globals().get("SPEECH_TIMEOUT_INBOUND", "3")   # 수신전화: 말 멈춰도 3초 대기
SPEECH_TIMEOUT_OUTBOUND = globals().get("SPEECH_TIMEOUT_OUTBOUND", "3")  # 발신전화(지인): 말 멈춰도 3초 대기 (전화받고 말할 여유 확보)
# 관리자 명령(일정 등록 등 긴 문장)은 더 넉넉하게 — 생각하며 말해도 안 끊기도록.
SPEECH_TIMEOUT_ADMIN    = globals().get("SPEECH_TIMEOUT_ADMIN", "2")     # 관리자 통화: 2초 대기 (긴 명령 대비, 이전 5초에서 단축)

TIMER_SUMMARY_START = 30.0   # 통화 종료 후 30초 후 요약 시작
TIMER_CALL_REPORT   = 35.0   # 요약 후 5초 뒤 보고 전화
TIMER_SMS_REPORT    = 40.0   # 요약 후 10초 뒤 보고 문자
TIMER_SMS_FAILURE   = 15.0   # 실패 시 15초 후 문자
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
# 수정 후 적용: cd ~/OpenWebUI && docker compose restart twilio-bot
# ═══════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════
# ⭐ 모드 적용 로직 (SERVICE_MODE = "personal" 일 때 개인용으로 전환)
# ═══════════════════════════════════════════════════════════
# 이 블록은 반드시 파일 맨 끝에 있어야 합니다(위의 모든 설정을 덮어쓰기 때문).
# SERVICE_MODE 가 "personal" 이면 아래 항목들을 개인용 기본값으로 바꿉니다.
# 고객전용("customer")일 때는 아무것도 바꾸지 않습니다(위 설정 그대로).
#
# ⚠️ 여기서 바꾸는 값이 마음에 안 들면, 이 블록보다 "위"에서 직접 값을 지정한 뒤
#    이 블록에서 다시 덮어쓰지 않도록 해당 줄을 주석 처리해도 됩니다.
try:
    _SERVICE_MODE = str(SERVICE_MODE).strip().lower()
except NameError:
    _SERVICE_MODE = "customer"

if _SERVICE_MODE == "personal":
    # (1) 상담원 0번 안내 멘트 OFF — 개인용은 굳이 "0번 누르세요" 안내 안 함
    #     (0번 직통 연결 '기능' 자체는 유지하되, 안내 멘트만 끔)
    OPERATOR_HINT_ENABLED = False

    # (2) 걸려온 전화 응대 성격을 '지인 안부'로 (상담체 → 안부체)
    #     ko/en/ja/zh 모두 개인용 톤으로 교체
    INBOUND_SYSTEM_PROMPTS = {
        "ko": (
            "당신은 친근하고 따뜻한 AI 전화 어시스턴트입니다. "
            "지금 걸려온 전화를 받고 있습니다. "
            "상대는 관리자님의 지인일 수 있으니 편안하고 따뜻하게 응대하세요. "
            "한국어 존댓말로 1~2문장 이내로 짧고 자연스럽게 답하세요. "
            "실제 사람처럼 '네', '아~', '그렇군요' 같은 추임새를 사용하세요. "
            "상대방이 더듬거나 불완전하게 말해도 문맥으로 이해하세요. "
            "상대방의 감정에 공감하며 반응하세요. "
            "'AI입니다'라고 밝히지 말고 자연스럽게 응대하세요. "
            "개인정보 보호: 관리자나 다른 사람의 전화번호·주소·개인정보를 절대 알려주지 마세요. "
            "번호나 개인정보를 물으면 '죄송하지만 개인정보는 알려드릴 수 없습니다'라고 정중히 거절하세요."
        ),
        "en": (
            "You are a friendly and warm AI phone assistant. "
            "You are answering an incoming call, possibly from an acquaintance of the admin. "
            "Respond warmly in English with 1-2 short, natural sentences. "
            "Use natural fillers like 'Sure', 'I see', 'Right'. "
            "Even if the caller stumbles, understand from context. "
            "Empathize with their emotions. "
            "Don't reveal you are an AI; respond naturally. "
            "Privacy: never reveal anyone's phone number, address, or personal info."
        ),
        "ja": (
            "あなたは親しみやすく温かいAI電話アシスタントです。 "
            "今、かかってきた電話を受けています。管理者様の知人かもしれないので温かく応対してください。 "
            "日本語の丁寧語で1～2文以内で短く自然に答えてください。 "
            "「はい」「あ～」「そうなんですね」などの相槌を使ってください。 "
            "相手が言葉に詰まっても文脈で理解してください。 "
            "「AIです」と明かさず自然に応対してください。 "
            "個人情報保護: 誰の電話番号・住所・個人情報も絶対に教えないでください。"
        ),
        "zh": (
            "你是一个友好而温暖的AI电话助手。 "
            "你正在接听来电，对方可能是管理员的熟人，请温暖地应对。 "
            "用中文礼貌用语在1-2句话内简短自然地回答。 "
            "使用'好的'、'是的'、'原来如此'等语气词。 "
            "即使对方说话结巴也要理解上下文。 "
            "不要表明自己是AI，自然地应对。 "
            "隐私保护: 绝不透露任何人的电话号码、地址或个人信息。"
        ),
    }
    INBOUND_SYSTEM_PROMPT = INBOUND_SYSTEM_PROMPTS[DEFAULT_LANG]

    # (3) 기본 인사말을 안부체로 교체 (걸려온 전화·발신전화 기본 인사)
    #     MESSAGES 딕셔너리의 GREETING_DEFAULT 만 언어별로 바꿈
    _PERSONAL_GREETINGS = {
        "ko": "안녕하세요! 잘 지내고 계시죠? 무엇을 도와드릴까요?",
        "en": "Hello! How have you been? How can I help you?",
        "ja": "こんにちは！お元気ですか？何かお手伝いしましょうか？",
        "zh": "您好！最近过得怎么样？有什么可以帮您的吗？",
    }
    for _lang, _greet in _PERSONAL_GREETINGS.items():
        if _lang in MESSAGES:
            MESSAGES[_lang]["GREETING_DEFAULT"] = _greet
    # MSG_ 호환 변수도 동기화
    MSG_GREETING_DEFAULT = MESSAGES[DEFAULT_LANG]["GREETING_DEFAULT"]

    # (4) AI 비서 이름/역할 라벨 (원하면 자유롭게 수정)
    AI_NAME = "AI 비서"
    AI_ROLE = "개인 전화 어시스턴트"

    # (5) 능동형 자동전화(기억의 앵커)는 개인용에서만 의미가 있으므로
    #     '켤 수 있도록' 열어둡니다. 실제로 켜려면 아래 값을 True 로 바꾸세요.
    #     기본은 안전을 위해 False(반응형)로 둡니다.
    # MEMORY_AUTOCALL_ENABLED = True   # ← 능동형 자동전화를 켜려면 주석 해제
    # MEMORY_AUTOCALL_MODE    = "suggest"  # "suggest"(제안) / "auto"(자동발신)

    print("🏠 서비스 모드: 개인용(personal) — 지인 안부 응대 / 상담 안내 멘트 OFF")
else:
    # 고객전용(customer) — 위에서 정의한 상담용 설정을 그대로 사용
    AI_ROLE = "고객 상담 어시스턴트"
    print("🏢 서비스 모드: 고객전용(customer) — 고객 상담 응대 / 상담원 0번 안내 ON")

# 수정 후 적용: cd ~/OpenWebUI && docker compose restart twilio-bot
# ═══════════════════════════════════════════════════════════
AICEOF

# 설치 시 선택한 서비스 모드(고객전용/개인용)를 ai_config.py 에 반영
# (heredoc 은 'customer' 로 고정 생성되므로, 선택값이 personal 이면 여기서 교체)
sed -i "s|^SERVICE_MODE = \"customer\"   #|SERVICE_MODE = \"${SERVICE_MODE}\"   #|" twilio-bot/ai_config.py
echo "   ✅ 서비스 모드 반영: SERVICE_MODE=\"${SERVICE_MODE}\""

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
                    loaded = json.load(f)
                # JSON 파일이 리스트로 저장된 경우 딕셔너리로 변환
                if isinstance(loaded, dict):
                    self.schedules = loaded
                elif isinstance(loaded, list):
                    self.schedules = {}
                    for item in loaded:
                        if isinstance(item, dict) and "id" in item:
                            self.schedules[item["id"]] = item
                    print(f"⚠️ 스케줄 파일 형식 변환 (list→dict): {len(self.schedules)}건")
                else:
                    self.schedules = {}
                print(f"📅 스케줄 로드: {len(self.schedules)}건")
            else:
                self.schedules = {}
        except Exception as e:
            print(f"⚠️ 스케줄 로드 실패: {e}")
            self.schedules = {}

    # ── 예약 추가 ─────────────────────────────
    def add(self, name, contact_name, action, schedule_time, repeat=None, mission="안부 확인", message="", enabled=True, report_to="", cal_title=None, cal_start=None):
        """
        action: "call" 또는 "sms"
        schedule_time: "2025-01-15 15:00" (1회) 또는 "15:00" (반복시 시간만)
        repeat: None(1회), "daily", "weekly:월", "weekly:화", "monthly:15" 등
        report_to: 보고받을 전화번호 (비우면 관리자에게 보고)
        cal_title / cal_start: 캘린더 일정 알림인 경우, 발송 직전 존재 확인용.
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
            "report_to": report_to,
            "cal_title": cal_title,
            "cal_start": cal_start,
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

    # ── 캘린더 일정 알림 제거 (일정 수정/삭제 시 옛 알림 취소용) ──
    def remove_calendar_reminders(self, cal_title, cal_start=None):
        """특정 캘린더 일정(cal_title [+ cal_start])에 걸린 self-reminder 예약을 모두 제거.
        cal_start 를 주면 제목+시작시각이 모두 일치하는 것만, 안 주면 제목만 일치하면 제거.
        반환: 제거한 예약 개수."""
        title = (cal_title or "").strip()
        if not title:
            return 0
        try:
            cs = int(cal_start) if cal_start is not None else None
        except (TypeError, ValueError):
            cs = None
        to_remove = []
        for sid, s in self.schedules.items():
            if s.get("contact_name") != "__self_reminder__":
                continue
            if (s.get("cal_title") or "").strip() != title:
                continue
            if cs is not None:
                try:
                    if int(s.get("cal_start") or 0) != cs:
                        continue
                except (TypeError, ValueError):
                    continue
            to_remove.append(sid)
        for sid in to_remove:
            self.schedules.pop(sid, None)
        if to_remove:
            self.save()
        return len(to_remove)

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
        stale_ids = []  # 지난 캘린더 알림(__self_reminder__) — 조용히 정리할 대상
        for sid, s in self.schedules.items():
            if not s["enabled"]:
                continue
            if s["repeat"]:
                continue  # 반복 예약은 놓침 처리 안 함 (다음에 실행)
            try:
                sched_dt = datetime.strptime(s["schedule_time"], "%Y-%m-%d %H:%M")
                if sched_dt < now and s["last_run"] is None:
                    # 📅 캘린더 일정 알림은 놓쳤어도 전화/문자/보고 없이 조용히 폐기.
                    #    (봇이 꺼져 있던 사이 지난 알림이 뒤늦게 오는 것을 방지)
                    if s.get("contact_name") == "__self_reminder__":
                        stale_ids.append(sid)
                        continue
                    missed.append({"sid": sid, **s})
            except Exception:
                continue
        # 지난 캘린더 알림 예약은 목록에서 제거(다시는 실행/보고되지 않도록)
        if stale_ids:
            for sid in stale_ids:
                self.schedules.pop(sid, None)
            self.save()
            print(f"🧹 지난 캘린더 알림 {len(stale_ids)}건 자동 정리 (전화·문자 발송 안 함)")
        return missed

    # ── 실행 시간 확인 ────────────────────────
    def _should_run(self, s):
        now = datetime.now()
        today_str = now.strftime("%Y-%m-%d")

        if not s["repeat"]:
            # 1회 예약
            try:
                sched_dt = datetime.strptime(s["schedule_time"], "%Y-%m-%d %H:%M")
                delta = (now - sched_dt).total_seconds()
                # 📅 캘린더 일정 알림: 예약 시각을 이미 지났으면(delta > 0 을 넘겨 여유 5초 초과) 실행 안 함.
                #    봇이 꺼졌다 늦게 켜져도 지난 알림 전화가 오지 않도록 미래 방향만 허용.
                if s.get("contact_name") == "__self_reminder__":
                    return -45 < delta <= 5
                return abs(delta) < 45
            except Exception:
                return False
        else:
            # 반복 예약 — 시간 확인
            try:
                sched_time = s["schedule_time"]  # "15:00" 형식
                target = datetime.strptime(f"{today_str} {sched_time}", "%Y-%m-%d %H:%M")
                if abs((now - target).total_seconds()) > 45:
                    return False
            except Exception:
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
    except Exception:
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


# ── twilio-bot entrypoint (볼륨 마운트 권한 수정) ──
cat > twilio-bot/entrypoint.sh <<'ENTRYEOF'
#!/bin/bash
set -e

# 디렉토리 존재 확인 (권한은 호스트에서 미리 설정 — chown 1001:1001)
mkdir -p /app/data/recordings /app/data/reports /app/logs 2>/dev/null || true
exec "$@"
ENTRYEOF
chmod +x twilio-bot/entrypoint.sh

cat > twilio-bot/Dockerfile <<'EOF'
FROM python:3.11-slim
LABEL maintainer="webmaster@vulva.sex"
LABEL version="1.1.0-hardened"

# 보안: non-root 사용자 (고정 UID 1001 — 호스트 chown과 일치)
RUN groupadd -r -g 1001 botuser && useradd -r -g botuser -u 1001 -m -s /sbin/nologin botuser

WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl fonts-nanum && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY twilio_bot.py .
COPY ai_config.py .
COPY scheduler.py .
COPY call_history.py .
COPY entrypoint.sh /entrypoint.sh
RUN mkdir -p /app/data/recordings /app/data/reports /app/logs && \
    chown -R botuser:botuser /app && \
    chmod +x /entrypoint.sh
EXPOSE 5000
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1
USER botuser
ENTRYPOINT ["/entrypoint.sh"]
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--timeout", "60", "--access-logfile", "-", "twilio_bot:app"]
EOF


############################################
# 10-4. 🎙️ realtime-voice (진짜 실시간 Media Streams 서버)
#      제작자: <webmaster@vulva.sex>
#  Twilio <Connect><Stream> 양방향 오디오를 받아 STT→LLM→TTS 파이프라인으로
#  진짜 실시간 대화(말 도중 끼어들기 barge-in)를 처리한다.
#  STT/TTS 제공자·키·음성은 밸브(voice_config.json)에서 런타임 교체 가능.
############################################
mkdir -p "$BASE_DIR/realtime-voice"

cat > realtime-voice/requirements.txt <<'EOF'
websockets>=14.0
aiohttp>=3.9.0
EOF

cat > realtime-voice/Dockerfile <<'EOF'
FROM python:3.11-slim
LABEL maintainer="webmaster@vulva.sex"
RUN groupadd -r -g 1002 rtuser && useradd -r -g rtuser -u 1002 -m -s /sbin/nologin rtuser
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY realtime_server.py .
RUN mkdir -p /app/data && chown -R rtuser:rtuser /app
EXPOSE 5001
USER rtuser
CMD ["python3", "realtime_server.py"]
EOF

cat > realtime-voice/realtime_server.py <<'RTEOF'
#!/usr/bin/env python3
# =============================================================================
# realtime-voice — Twilio Media Streams 기반 진짜 실시간 AI 대리통화 서버
# 제작자: <webmaster@vulva.sex>
#
#  ▸ Twilio <Connect><Stream> 양방향 오디오(mulaw 8kHz)를 WebSocket으로 수신
#  ▸ STT(Deepgram 등)로 실시간 전사 → LLM(Groq/OpenWebUI) → TTS(ElevenLabs 등)
#  ▸ 상대방이 말하기 시작하면(interim transcript) 즉시 barge-in:
#      - TTS 청크 전송 중단 + Twilio 로 clear 메시지 → 재생 중 오디오 즉시 끊김
#  ▸ 🤫 실시간 귓속말: twilio-bot 의 /whisper 큐를 폴링해서
#      다음 LLM 프롬프트 최상단에 관리자 지시를 최우선 주입
#  ▸ STT/TTS 제공자·키·음성은 /app/data/voice_config.json (밸브에서 저장) 로
#      런타임 교체 가능. 파일이 없으면 환경변수 기본값 사용.
#
#  포트: 5001 (내부)  |  경로: /twilio-stream (Twilio가 wss로 접속)
# =============================================================================
import os
import json
import base64
import asyncio
import urllib.request

import websockets
# websockets 버전 호환: 14+ 는 asyncio.server, 그 이하는 legacy(server)
try:
    from websockets.asyncio.server import serve
except ImportError:
    from websockets.server import serve

# ── 기본 설정 (환경변수 → voice_config.json 이 있으면 덮어씀) ──────────────
DATA_DIR         = os.getenv("DATA_DIR", "/app/data")
VOICE_CONFIG     = os.path.join(DATA_DIR, "voice_config.json")
TWILIO_BOT_URL   = os.getenv("TWILIO_BOT_URL", "http://twilio-bot:5000")
API_SECRET       = os.getenv("API_SECRET", "")

# LLM (기존 봇과 동일 소스 재사용)
GROQ_API_KEY     = os.getenv("OPENAI_API_KEY", "") or os.getenv("GROQ_API_KEY", "")
GROQ_API_URL     = "https://api.groq.com/openai/v1/chat/completions"
LLM_MODEL        = os.getenv("MODEL", "llama-3.3-70b-versatile")

# 기본 제공자 (밸브 미설정 시)
DEFAULT_CFG = {
    "stt_provider": os.getenv("STT_PROVIDER", "deepgram"),   # deepgram | groq_whisper | twilio(=미지원 안내)
    "stt_api_key":  os.getenv("DEEPGRAM_API_KEY", ""),
    "stt_model":    os.getenv("STT_MODEL", "nova-2"),
    "tts_provider": os.getenv("TTS_PROVIDER", "elevenlabs"), # elevenlabs | deepgram | openai
    "tts_api_key":  os.getenv("ELEVENLABS_API_KEY", ""),
    "tts_voice":    os.getenv("TTS_VOICE", "21m00Tcm4TlvDq8ikWAM"),  # ElevenLabs 기본 Rachel
    "tts_model":    os.getenv("TTS_MODEL", "eleven_flash_v2_5"),
    "language":     os.getenv("REALTIME_LANG", "ko"),
    "system_prompt": os.getenv(
        "REALTIME_SYSTEM_PROMPT",
        "당신은 전화로 상대방과 대화하는 따뜻하고 자연스러운 AI 비서입니다. "
        "한 번에 1~2문장으로 짧고 공감 있게 말하세요. AI라는 티를 내지 마세요."
    ),
}


def load_config():
    """밸브에서 저장한 voice_config.json 을 읽어 기본값 위에 덮어쓴다."""
    cfg = dict(DEFAULT_CFG)
    try:
        if os.path.exists(VOICE_CONFIG):
            with open(VOICE_CONFIG, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    for k, v in data.items():
                        if v not in (None, ""):
                            cfg[k] = v
    except Exception as e:
        print(f"⚠️ voice_config 로드 실패 (기본값 사용): {e}", flush=True)
    return cfg


# ── LLM 호출 (Groq 우선, 간결) ────────────────────────────────────────────
def llm_reply(history, system_prompt):
    """history: [{"role","content"},...] → 한 문장 응답 문자열"""
    if not GROQ_API_KEY:
        return "죄송합니다. 지금은 답변을 드리기 어렵습니다."
    messages = [{"role": "system", "content": system_prompt}] + history
    payload = json.dumps({
        "model": LLM_MODEL,
        "messages": messages,
        "max_tokens": 120,
        "temperature": 0.3,
    }).encode()
    req = urllib.request.Request(
        GROQ_API_URL,
        data=payload,
        headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            return data["choices"][0]["message"]["content"].strip()
    except Exception as e:
        print(f"⚠️ LLM 오류: {e}", flush=True)
        return "네, 말씀 계속 들을게요."


# ── 귓속말 큐 조회 (twilio-bot 의 기존 /whisper API 재사용) ────────────────
# ── 🧠 기억의 앵커: twilio-bot HTTP API 경유 ──────────────────
def recall_memory_prompt(phone_number, name, query):
    """통화 초반에 과거 회상 프롬프트를 가져온다 (없으면 '')."""
    if not API_SECRET:
        return ""
    try:
        body = json.dumps({"phone_number": phone_number, "name": name, "query": query}).encode()
        req = urllib.request.Request(
            f"{TWILIO_BOT_URL}/memory/recall", data=body,
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return (json.loads(resp.read()).get("prompt") or "").strip()
    except Exception:
        return ""

def save_memory(phone_number, name, text, summary=""):
    """통화 종료 시 대화를 저장 API 로 전송."""
    if not API_SECRET or not (text or "").strip():
        return
    try:
        body = json.dumps({"phone_number": phone_number, "name": name,
                           "text": text, "summary": summary}).encode()
        req = urllib.request.Request(
            f"{TWILIO_BOT_URL}/memory/save", data=body,
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=8).read()
    except Exception as e:
        print(f"⚠️ 기억 저장 전송 실패(무시): {e}", flush=True)

def fetch_whisper(call_sid):
    """이 통화(call_sid)에 대기 중인 관리자 지시를 가져와 비운다.
       twilio-bot 의 /whisper/send 는 target 으로 call_sid 를 받도록 이미 구현됨.
       여기서는 pop 전용 내부 엔드포인트(/whisper/pop)를 호출한다."""
    if not API_SECRET:
        return ""
    try:
        body = json.dumps({"call_sid": call_sid}).encode()
        req = urllib.request.Request(
            f"{TWILIO_BOT_URL}/whisper/pop",
            data=body,
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read())
            return (data.get("instruction") or "").strip()
    except Exception:
        return ""


def register_realtime_call(call_sid, name, number, direction):
    """진행 중 통화를 twilio-bot 에 등록(귓속말 대상 목록에 노출)."""
    if not API_SECRET or not call_sid:
        return
    try:
        body = json.dumps({
            "call_sid": call_sid, "name": name, "number": number, "direction": direction
        }).encode()
        req = urllib.request.Request(
            f"{TWILIO_BOT_URL}/whisper/register",
            data=body,
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=3).read()
    except Exception:
        pass


def unregister_realtime_call(call_sid):
    if not API_SECRET or not call_sid:
        return
    try:
        body = json.dumps({"call_sid": call_sid}).encode()
        req = urllib.request.Request(
            f"{TWILIO_BOT_URL}/whisper/unregister",
            data=body,
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=3).read()
    except Exception:
        pass


# ════════════════════════════════════════════════════════════════════════
#  STT 어댑터 — 제공자별로 mulaw 8kHz 오디오를 받아 전사 이벤트를 콜백
#  콜백 시그니처: on_transcript(text, is_final)
# ════════════════════════════════════════════════════════════════════════
class DeepgramSTT:
    """Deepgram 실시간 STT. mulaw 8kHz 그대로 전송."""
    def __init__(self, cfg, on_transcript, loop):
        self.cfg = cfg
        self.on_transcript = on_transcript
        self.loop = loop
        self.ws = None
        self._task = None

    async def start(self):
        key = self.cfg.get("stt_api_key", "")
        model = self.cfg.get("stt_model", "nova-2")
        lang = self.cfg.get("language", "ko")
        url = (
            "wss://api.deepgram.com/v1/listen"
            f"?encoding=mulaw&sample_rate=8000&channels=1"
            f"&model={model}&language={lang}"
            "&interim_results=true&punctuate=true&endpointing=300"
        )
        # websockets 버전 호환: 14+ 는 additional_headers, 13 이하는 extra_headers
        _auth = {"Authorization": f"Token {key}"}
        try:
            self.ws = await websockets.connect(url, additional_headers=_auth)
        except TypeError:
            self.ws = await websockets.connect(url, extra_headers=_auth)
        self._task = asyncio.create_task(self._recv())

    async def _recv(self):
        try:
            async for msg in self.ws:
                data = json.loads(msg)
                if data.get("type") != "Results":
                    continue
                alt = (data.get("channel", {}).get("alternatives") or [{}])[0]
                text = (alt.get("transcript") or "").strip()
                if not text:
                    continue
                is_final = bool(data.get("is_final"))
                await self.on_transcript(text, is_final)
        except Exception as e:
            print(f"⚠️ Deepgram 수신 종료: {e}", flush=True)

    async def send_audio(self, mulaw_bytes):
        if self.ws:
            try:
                await self.ws.send(mulaw_bytes)
            except Exception:
                pass

    async def close(self):
        try:
            if self.ws:
                await self.ws.send(json.dumps({"type": "CloseStream"}))
                await self.ws.close()
        except Exception:
            pass


def make_stt(cfg, on_transcript, loop):
    provider = (cfg.get("stt_provider") or "deepgram").lower()
    if provider == "deepgram":
        return DeepgramSTT(cfg, on_transcript, loop)
    # groq_whisper 등은 청크 버퍼링 방식이라 별도 구현 필요 — 기본은 Deepgram
    print(f"ℹ️ STT provider '{provider}' 미구현 → Deepgram 으로 대체", flush=True)
    return DeepgramSTT(cfg, on_transcript, loop)


# ════════════════════════════════════════════════════════════════════════
#  TTS 어댑터 — 텍스트를 mulaw 8kHz 오디오 청크(bytes)로 스트리밍
#  async generator: yield mulaw_chunk_bytes
# ════════════════════════════════════════════════════════════════════════
async def elevenlabs_tts_stream(cfg, text):
    """ElevenLabs Flash v2.5, output_format=ulaw_8000 → Twilio 로 바로 전달 가능."""
    import aiohttp
    voice = cfg.get("tts_voice", "21m00Tcm4TlvDq8ikWAM")
    model = cfg.get("tts_model", "eleven_flash_v2_5")
    key = cfg.get("tts_api_key", "")
    url = (
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice}/stream"
        f"?output_format=ulaw_8000&optimize_streaming_latency=4"
    )
    payload = {
        "text": text,
        "model_id": model,
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
    }
    async with aiohttp.ClientSession() as sess:
        async with sess.post(url, json=payload,
                             headers={"xi-api-key": key, "Content-Type": "application/json"}) as resp:
            if resp.status != 200:
                err = await resp.text()
                print(f"⚠️ ElevenLabs TTS 오류 {resp.status}: {err[:200]}", flush=True)
                return
            async for chunk in resp.content.iter_chunked(1600):  # ~200ms of ulaw@8k
                if chunk:
                    yield chunk


async def deepgram_tts_stream(cfg, text):
    """Deepgram Aura TTS, raw mulaw 8000 → Twilio 로 바로 전달."""
    import aiohttp
    key = cfg.get("tts_api_key", "")
    model = cfg.get("tts_model", "aura-asteria-en")
    url = f"https://api.deepgram.com/v1/speak?model={model}&encoding=mulaw&sample_rate=8000&container=none"
    async with aiohttp.ClientSession() as sess:
        async with sess.post(url, json={"text": text},
                             headers={"Authorization": f"Token {key}", "Content-Type": "application/json"}) as resp:
            if resp.status != 200:
                err = await resp.text()
                print(f"⚠️ Deepgram TTS 오류 {resp.status}: {err[:200]}", flush=True)
                return
            async for chunk in resp.content.iter_chunked(1600):
                if chunk:
                    yield chunk


def make_tts_stream(cfg, text):
    provider = (cfg.get("tts_provider") or "elevenlabs").lower()
    if provider == "deepgram":
        return deepgram_tts_stream(cfg, text)
    return elevenlabs_tts_stream(cfg, text)


# ════════════════════════════════════════════════════════════════════════
#  통화 세션 — 하나의 Twilio Stream WebSocket 당 하나
# ════════════════════════════════════════════════════════════════════════
class CallSession:
    def __init__(self, twilio_ws):
        self.twilio_ws = twilio_ws
        self.stream_sid = None
        self.call_sid = None
        self.name = "상대방"
        self.number = ""
        self.direction = "inbound"
        self.cfg = load_config()
        self.history = []            # LLM 대화 히스토리
        self.stt = None
        self.loop = asyncio.get_event_loop()

        self.speaking = False        # 지금 AI가 말하는 중인가
        self.tts_task = None         # 현재 TTS 재생 태스크
        self.interrupt = False       # barge-in 플래그
        self._final_buffer = ""      # 확정 전사 누적
        self._greeted = False

    # ── Twilio 로 오디오 전송 ──
    async def _send_media(self, mulaw_chunk):
        if not self.stream_sid:
            return
        msg = {
            "event": "media",
            "streamSid": self.stream_sid,
            "media": {"payload": base64.b64encode(mulaw_chunk).decode()},
        }
        await self.twilio_ws.send(json.dumps(msg))

    async def _send_clear(self):
        """Twilio 재생 버퍼 즉시 비우기 (barge-in 시 말 끊기)."""
        if not self.stream_sid:
            return
        await self.twilio_ws.send(json.dumps({"event": "clear", "streamSid": self.stream_sid}))

    async def _send_mark(self, name):
        await self.twilio_ws.send(json.dumps({
            "event": "mark", "streamSid": self.stream_sid, "mark": {"name": name}
        }))

    # ── AI 발화: TTS 스트리밍 (도중 barge-in 되면 중단) ──
    async def speak(self, text):
        text = (text or "").strip()
        if not text:
            return
        self.speaking = True
        self.interrupt = False
        print(f"🤖 AI: {text}", flush=True)
        try:
            async for chunk in make_tts_stream(self.cfg, text):
                if self.interrupt:
                    print("✋ barge-in → TTS 중단", flush=True)
                    break
                # 20ms(160바이트) 단위로 잘라 전송 → 끊김 없이 자연스럽게
                for i in range(0, len(chunk), 160):
                    if self.interrupt:
                        break
                    await self._send_media(chunk[i:i+160])
                    await asyncio.sleep(0.018)
        except asyncio.CancelledError:
            # barge-in 등으로 태스크가 취소됨 — 정상 흐름
            pass
        except Exception as e:
            print(f"⚠️ speak 오류: {e}", flush=True)
        finally:
            self.speaking = False

    def _start_speak(self, text):
        # 이전 발화가 진행 중이면 플래그로 중단 신호 → 자연 종료 유도
        if self.tts_task and not self.tts_task.done():
            self.interrupt = True
            self.tts_task.cancel()
        self.tts_task = asyncio.create_task(self.speak(text))

    async def _barge_in(self):
        """상대방이 말을 시작 → 즉시 AI 발화 중단 + Twilio 버퍼 클리어."""
        if self.speaking:
            self.interrupt = True   # speak() 루프가 다음 청크에서 스스로 멈춤
            if self.tts_task and not self.tts_task.done():
                self.tts_task.cancel()
            await self._send_clear()

    # ── STT 콜백 ──
    async def on_transcript(self, text, is_final):
        # interim(중간) 전사가 잡히면 = 상대가 말하는 중 → barge-in
        if not is_final:
            await self._barge_in()
            return
        # 확정 전사 → LLM 턴
        self._final_buffer = (self._final_buffer + " " + text).strip()
        print(f"🗣️ {self.name}: {self._final_buffer}", flush=True)

        # 관리자 귓속말 조회 → 있으면 프롬프트 최우선 주입
        whisper = fetch_whisper(self.call_sid)
        sys_prompt = self.cfg.get("system_prompt", "")
        if whisper:
            sys_prompt = (
                "【관리자 실시간 지시 — 최우선】 다음 내용을 다음 발화에 자연스럽게 녹여 말하세요. "
                "지시받았다는 티는 내지 마세요.\n지시: \"" + whisper + "\"\n\n" + sys_prompt
            )
            print(f"🎯 귓속말 반영: {whisper[:50]}", flush=True)

        self.history.append({"role": "user", "content": self._final_buffer})
        self._final_buffer = ""

        reply = await asyncio.get_event_loop().run_in_executor(
            None, llm_reply, self.history, sys_prompt
        )
        self.history.append({"role": "assistant", "content": reply})
        self._start_speak(reply)

    # ── 메인 루프: Twilio WebSocket 메시지 처리 ──
    async def run(self):
        async for raw in self.twilio_ws:
            data = json.loads(raw)
            ev = data.get("event")

            if ev == "start":
                s = data["start"]
                self.stream_sid = s["streamSid"]
                self.call_sid = s.get("callSid", "")
                params = s.get("customParameters", {}) or {}
                self.name = params.get("name", self.name)
                self.number = params.get("number", "")
                self.direction = params.get("direction", "inbound")
                # 밸브 설정 재로딩 (통화 시작 시점 최신값)
                self.cfg = load_config()
                if params.get("system_prompt"):
                    self.cfg["system_prompt"] = params["system_prompt"]
                print(f"📞 스트림 시작: {self.name}({self.number}) sid={self.call_sid}", flush=True)
                register_realtime_call(self.call_sid, self.name, self.number, self.direction)
                # 🧠 기억의 앵커: 과거 회상을 시스템 프롬프트에 주입 (있으면)
                try:
                    mem_prompt = await asyncio.get_event_loop().run_in_executor(
                        None, recall_memory_prompt, self.number, self.name, self.name + " 통화"
                    )
                    if mem_prompt:
                        self.cfg["system_prompt"] = (self.cfg.get("system_prompt", "") + "\n\n" + mem_prompt).strip()
                        print(f"🧠 기억 회상 주입: {self.name}", flush=True)
                except Exception as _me:
                    print(f"⚠️ 기억 회상 주입 실패(무시): {_me}", flush=True)
                # STT 시작
                self.stt = make_stt(self.cfg, self.on_transcript, self.loop)
                await self.stt.start()
                # 첫 인사 (대리전화면 관리자 메시지, 아니면 기본)
                if not self._greeted:
                    self._greeted = True
                    greet = params.get("greeting") or "여보세요, 안녕하세요. 무엇을 도와드릴까요?"
                    self.history.append({"role": "assistant", "content": greet})
                    self._start_speak(greet)

            elif ev == "media":
                payload = data["media"]["payload"]
                mulaw = base64.b64decode(payload)
                if self.stt:
                    await self.stt.send_audio(mulaw)

            elif ev == "mark":
                pass  # 재생 완료 표식 (필요 시 활용)

            elif ev == "stop":
                print(f"📴 스트림 종료: {self.call_sid}", flush=True)
                break

        # 정리
        if self.stt:
            await self.stt.close()
        # 🧠 기억의 앵커: 통화 대화를 저장 (상대 발화가 있었을 때만)
        try:
            convo = "\n".join(
                f"{'AI' if m['role']=='assistant' else '상대'}: {m['content']}"
                for m in self.history if m.get("content")
            )
            has_user = any(m.get("role") == "user" for m in self.history)
            if has_user and convo.strip():
                await asyncio.get_event_loop().run_in_executor(
                    None, save_memory, self.number, self.name, convo, ""
                )
                print(f"🧠 기억 저장 요청: {self.name}", flush=True)
        except Exception as _me:
            print(f"⚠️ 기억 저장 실패(무시): {_me}", flush=True)
        unregister_realtime_call(self.call_sid)


async def handler(twilio_ws):
    session = CallSession(twilio_ws)
    try:
        await session.run()
    except websockets.ConnectionClosed:
        pass
    except Exception as e:
        print(f"⚠️ 세션 오류: {e}", flush=True)
    finally:
        unregister_realtime_call(session.call_sid)


async def main():
    port = int(os.getenv("REALTIME_PORT", "5001"))
    print(f"🎙️ realtime-voice 서버 시작 (포트 {port}, 경로 /twilio-stream)", flush=True)
    async with serve(handler, "0.0.0.0", port, max_size=None):
        await asyncio.Future()  # 영원히 실행


if __name__ == "__main__":
    asyncio.run(main())
RTEOF
echo "   ✅ realtime-voice 서버 파일 생성 완료"

############################################
# 11. OpenAPI Tool Server (동일)
############################################
cat > tools-api/requirements.txt <<EOF
# ⚠️ 최소 버전: CVE 패치 기준
fastapi>=0.115.0
uvicorn[standard]>=0.27.0
pydantic>=2.5.3
# CVE-2024-47081 (netrc 자격증명 유출) 패치
requests>=2.34.2
urllib3>=2.6.3
# CVE-2026-40347 (CVSS 5.3) DoS via multipart preamble
# CVE-2026-24486 (CVSS 7.5) Path Traversal
# CVE-2026-28356 (HIGH) ReDoS
python-multipart>=0.0.27
pypdf>=3.17.4
python-docx>=1.1.0
qdrant-client>=1.7.0
numpy>=1.26.3
ollama>=0.1.6
EOF

PYTHON_RETRIES=$((QDRANT_RETRIES / 2))

cat > tools-api/main.py <<EOF
from fastapi import FastAPI, UploadFile, File, HTTPException, Request, Depends
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os, uuid, time, csv, hmac, ipaddress, requests as http_requests
from pypdf import PdfReader
from docx import Document as DocxDocument
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
EMBED_DIM = int(os.getenv("EMBED_DIM", "768"))  # 🆕 성능별 임베딩 모델 차원 (384/768/1024)
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://172.17.0.1:11434")
DATA_DIR = "/app/data"
RAG_UNIFIED = os.getenv("RAG_UNIFIED_SEARCH", "true").lower() == "true"

# Twilio 봇 연동
TWILIO_BOT_URL = os.getenv("TWILIO_BOT_URL", "http://twilio-bot:5000")
API_SECRET = os.getenv("API_SECRET", "")

# ── 보안: 정확한 사설망(RFC1918) + 루프백 판별 ──
def _is_private_ip(ip: str) -> bool:
    """문자열 prefix 대신 ipaddress 모듈로 정확히 사설망/루프백 여부 판별"""
    if ip in ("localhost",):
        return True
    try:
        addr = ipaddress.ip_address(ip)
        return addr.is_private or addr.is_loopback
    except ValueError:
        return False

# ── 보안: 내부 API 인증 의존성 (X-API-Secret 헤더) ──
from fastapi import Header
def require_internal_secret(x_api_secret: str = Header(default="")):
    """tools-api 내부 엔드포인트 인증 (심층 방어). API_SECRET 미설정 시 차단(fail-closed)."""
    if not API_SECRET:
        # 🔒 설정 누락 시 통과(fail-open)가 아니라 차단. 설치 스크립트가 항상 생성하므로
        #    정상 환경에선 발생하지 않지만, 누락 시 무인증 노출을 막는다.
        raise HTTPException(status_code=503, detail="API secret not configured")
    if not hmac.compare_digest(x_api_secret or "", API_SECRET):
        raise HTTPException(status_code=401, detail="Unauthorized")
    return True

# 🔒 심층 방어: 위험한 조작 엔드포인트(전화·문자·연락처/일정 변경)를 내부망에서만 허용.
#    OpenWebUI 도구/twilio-bot 은 Docker 내부망(사설IP)에서 호출하므로 정상 통과하고,
#    호스트의 다른 로컬 프로세스나 외부 접근(공인IP)은 차단한다. 인증 헤더가 없어도 되어
#    기존 도구 호출을 깨지 않는다. (X-Forwarded-For 위조 시엔 헤더가 있으면 거부)
def require_internal_network(request: Request):
    # 프록시 경유(외부에서 들어온) 요청은 XFF/실제 프록시 헤더가 붙으므로 차단
    if request.headers.get("X-Forwarded-For") or request.headers.get("CF-Connecting-IP"):
        raise HTTPException(status_code=403, detail="Forbidden (external access not allowed)")
    client_ip = request.client.host if request.client else ""
    if not _is_private_ip(client_ip):
        raise HTTPException(status_code=403, detail="Forbidden (internal network only)")
    return True

# ── 보안: 업로드 크기 제한 (DoS 완화) ──
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_MB", "50")) * 1024 * 1024

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

CONTACTS_COLLECTION = "contacts"

if client:
    try:
        collections = [c.name for c in client.get_collections().collections]
        if COLLECTION not in collections:
            client.create_collection(
                collection_name=COLLECTION,
                vectors_config=VectorParams(size=EMBED_DIM, distance=Distance.COSINE),
            )
            print(f"✅ 컬렉션 생성: {COLLECTION}")
        else:
            print(f"✅ 기존 컬렉션 사용: {COLLECTION}")
        # 연락처 컬렉션 초기화
        if CONTACTS_COLLECTION not in collections:
            client.create_collection(
                collection_name=CONTACTS_COLLECTION,
                vectors_config=VectorParams(size=EMBED_DIM, distance=Distance.COSINE),
            )
            print(f"✅ 연락처 컬렉션 생성: {CONTACTS_COLLECTION}")
        else:
            print(f"✅ 연락처 컬렉션 사용: {CONTACTS_COLLECTION}")
    except Exception as e:
        print(f"❌ 컬렉션 생성 실패: {e}")

    print(f"📚 RAG 모드: {'통합 검색 (openapi_rag + OpenWebUI)' if RAG_UNIFIED else '분리 검색 (openapi_rag 전용)'}")

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

@app.post("/documents/upload", summary="Upload PDF/TXT/CSV/DOCX for RAG indexing")
async def upload_pdf(file: UploadFile = File(...), _auth: bool = Depends(require_internal_secret)):
    if not client:
        raise HTTPException(status_code=503, detail="Qdrant client not initialized")
    
    try:
        # ── 보안: 파일명 정제 (Path Traversal 방지) ──
        import re as _re
        safe_filename = file.filename or "unnamed"
        safe_filename = _re.sub(r'[^\w가-힣._-]', '_', safe_filename)  # 위험 문자 제거 (.., /, \ 등)
        if len(safe_filename) > 100:
            safe_filename = safe_filename[:100]

        path = os.path.realpath(os.path.join(DATA_DIR, safe_filename))
        if not path.startswith(os.path.realpath(DATA_DIR) + os.sep):
            raise HTTPException(status_code=403, detail="잘못된 파일 경로 (접근 거부)")

        # ── 보안: 업로드 크기 제한 (DoS 완화) ──
        content = await file.read()
        if len(content) > MAX_UPLOAD_BYTES:
            raise HTTPException(status_code=413, detail=f"파일이 너무 큽니다 (최대 {MAX_UPLOAD_BYTES // (1024*1024)}MB)")

        with open(path, "wb") as f:
            f.write(content)
        
        print(f"📄 파일 저장: {safe_filename}")

        # ── 1. 동일 파일 기존 벡터 삭제 (중복 방지) ──
        delete_existing_vectors(safe_filename)

        # ── 1-1. 파일 형식별 텍스트 추출 (PDF/TXT/CSV/DOCX 지원) ──
        fname = safe_filename.lower()
        if fname.endswith(".txt"):
            with open(path, "r", encoding="utf-8") as tf:
                text = tf.read()
            print(f"📝 TXT 텍스트 로드: {len(text)} 문자")
        elif fname.endswith(".csv"):
            with open(path, "r", encoding="utf-8") as cf:
                reader = csv.reader(cf)
                rows = [", ".join(row) for row in reader]
                text = "\n".join(rows)
            print(f"📝 CSV 텍스트 변환: {len(text)} 문자 ({len(rows)}행)")
        elif fname.endswith(".docx"):
            doc = DocxDocument(path)
            paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
            tables_text = []
            for table in doc.tables:
                for row in table.rows:
                    cells = [cell.text.strip() for cell in row.cells]
                    tables_text.append(", ".join(cells))
            text = "\n".join(paragraphs + tables_text)
            print(f"📝 DOCX 텍스트 추출: {len(text)} 문자 ({len(paragraphs)}단락, {len(doc.tables)}표)")
        else:
            reader = PdfReader(path)
            text = "".join(p.extract_text() or "" for p in reader.pages)
            print(f"📝 PDF 텍스트 추출: {len(text)} 문자")
        
        if not text.strip():
            raise HTTPException(status_code=400, detail="텍스트 추출 실패 (빈 파일)")

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
                            payload={"text": chunk, "source": safe_filename, "chunk_index": idx},
                        )
                    )
            
            print(f"🔢 임베딩 진행: {min(batch_start + batch_size, len(chunks))}/{len(chunks)}")

        if not points:
            raise HTTPException(status_code=500, detail="임베딩 실패")

        client.upsert(collection_name=COLLECTION, points=points)
        print(f"💾 저장 완료: {len(points)}개 (중복 제거 후)")
        
        return {
            "status": "success",
            "filename": safe_filename,
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
    top_k: int = 5
    unified: bool | None = None  # 🆕 요청별 검색 범위 오버라이드 (None이면 .env 기본값 사용)

# OpenWebUI 컬렉션도 함께 검색 (통합 모드일 때만)
# (참고) 아래는 .env 기본값 기준 컬렉션 목록. 실제 검색 범위는 요청별로
# rag_search 안에서 _owui_cols 로 결정한다(개인용 전환 시 unified 오버라이드).
OWUI_COLLECTIONS = ["open-webui_files", "open-webui_knowledge"] if RAG_UNIFIED else []

@app.post("/rag/search", summary="Unified RAG search (openapi_rag + OpenWebUI)")
def rag_search(search: SearchQuery):
    if not client:
        raise HTTPException(status_code=503, detail="Qdrant client not initialized")
    
    try:
        query_vector = embed(search.query)
        all_results = []
        searched = []
        # 🆕 요청에 unified 가 오면 그 값을 우선(개인용 전환 시 twilio-bot 이 통합 요청),
        #    없으면 .env 기본값(RAG_UNIFIED) 사용.
        _unified = RAG_UNIFIED if search.unified is None else search.unified
        _owui_cols = ["open-webui_files", "open-webui_knowledge"] if _unified else []

        # ── 1. openapi_rag 컬렉션 검색 ──
        try:
            hits = client.search(
                collection_name=COLLECTION,
                query_vector=query_vector,
                limit=search.top_k,
            )
            for h in hits:
                all_results.append({
                    "text": h.payload.get("text", ""),
                    "source": h.payload.get("source", ""),
                    "chunk_index": h.payload.get("chunk_index", 0),
                    "score": h.score,
                    "collection": COLLECTION
                })
            searched.append(COLLECTION)
        except Exception as e:
            print(f"⚠️ {COLLECTION} 검색 스킵: {e}")

        # ── 2. OpenWebUI 컬렉션 검색 (통합 모드일 때만) ──
        for owui_col in _owui_cols:
            try:
                hits = client.search(
                    collection_name=owui_col,
                    query_vector=query_vector,
                    limit=search.top_k,
                )
                for h in hits:
                    all_results.append({
                        "text": h.payload.get("text", ""),
                        "source": h.payload.get("metadata", {}).get("source", owui_col),
                        "chunk_index": 0,
                        "score": h.score,
                        "collection": owui_col
                    })
                searched.append(owui_col)
            except Exception:
                pass  # 컬렉션 미존재 또는 차원 불일치 시 무시

        # ── 3. 점수 기준 정렬 후 상위 top_k 반환 ──
        all_results.sort(key=lambda x: x["score"], reverse=True)
        results = all_results[:search.top_k]
        
        if results:
            print(f"📚 RAG 통합검색 ({', '.join(searched)}): {len(results)}건, 최고점수={results[0]['score']:.3f}")

        return {"query": search.query, "results": results, "count": len(results), "searched_collections": searched}
        
    except Exception as e:
        print(f"❌ 검색 오류: {e}")
        raise HTTPException(status_code=500, detail=f"Search error: {str(e)}")

# 전화용 RAG 문서 목록 조회
@app.get("/documents/list", summary="List uploaded RAG documents")
def list_documents():
    try:
        files = []
        if os.path.exists(DATA_DIR):
            for fname in sorted(os.listdir(DATA_DIR)):
                if fname.lower().endswith((".pdf", ".txt", ".csv", ".docx")):
                    fpath = os.path.join(DATA_DIR, fname)
                    size = os.path.getsize(fpath)
                    files.append({
                        "filename": fname,
                        "size_kb": round(size / 1024, 1),
                    })
        
        # Qdrant 벡터 수 조회
        vector_count = 0
        if client:
            try:
                info = client.get_collection(COLLECTION)
                vector_count = info.points_count
            except Exception:
                pass

        return {
            "files": files,
            "total_files": len(files),
            "total_vectors": vector_count,
            "collection": COLLECTION
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"List error: {str(e)}")

# 전화 Tool
class CallMeRequest(BaseModel):
    message: str = ""

class CallContactRequest(BaseModel):
    name: str
    mission: str = "안부 확인"
    message: str = ""
    report_to: str = ""

@app.post("/tools/call-me", summary="Call admin")
def tool_call_me(req: CallMeRequest, _net: bool = Depends(require_internal_network)):
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
def tool_call_contact(req: CallContactRequest, _net: bool = Depends(require_internal_network)):
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/call-contact",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json={"name": req.name, "mission": req.mission, "message": req.message, "report_to": req.report_to},
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
def tool_send_sms(req: SendSMSRequest, _net: bool = Depends(require_internal_network)):
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


# ═══════════════════════════════════════════════════════════════
# 🔟 실시간 귓속말 (AI 대리통화 라이브 지시) — twilio-bot 프록시
# ═══════════════════════════════════════════════════════════════
class WhisperSendRequest(BaseModel):
    instruction: str
    target: str = ""

class WhisperTargetRequest(BaseModel):
    target: str = ""

@app.get("/tools/whisper/active-calls", summary="List active (in-progress) calls")
def tool_whisper_active_calls():
    """지금 진행 중인 통화 목록을 반환합니다."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.get(
            f"{TWILIO_BOT_URL}/whisper/active-calls",
            headers={"X-API-Secret": API_SECRET},
            timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/tools/whisper/send", summary="Send live whisper instruction to an ongoing call")
def tool_whisper_send(req: WhisperSendRequest, _net: bool = Depends(require_internal_network)):
    """진행 중인 통화에 실시간 지시를 전달합니다 (다음 발화에 반영)."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/whisper/send",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json={"instruction": req.instruction, "target": req.target},
            timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/tools/whisper/clear", summary="Clear pending whisper instructions")
def tool_whisper_clear(req: WhisperTargetRequest, _net: bool = Depends(require_internal_network)):
    """대기 중인 실시간 지시를 취소합니다."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/whisper/clear",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json={"target": req.target},
            timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 🎙️ 음성엔진(STT/TTS) 설정 — 밸브 저장/조회 프록시 ──────────────
class VoiceConfigRequest(BaseModel):
    stt_provider: str = ""
    stt_api_key: str = ""
    stt_model: str = ""
    tts_provider: str = ""
    tts_api_key: str = ""
    tts_voice: str = ""
    tts_model: str = ""
    language: str = ""
    system_prompt: str = ""

@app.get("/tools/voice-config", summary="Get current STT/TTS engine config")
def tool_voice_config_get():
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.get(
            f"{TWILIO_BOT_URL}/voice-config",
            headers={"X-API-Secret": API_SECRET},
            timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/tools/voice-config", summary="Save STT/TTS engine config (valve)")
def tool_voice_config_set(req: VoiceConfigRequest, _net: bool = Depends(require_internal_network)):
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/voice-config",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json=req.dict(),
            timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 🧠 기억의 앵커 프록시 ──────────────────────────────
class MemoryRecallRequest(BaseModel):
    phone_number: str = ""
    name: str = ""
    query: str = ""

class MemorySaveRequest(BaseModel):
    phone_number: str = ""
    name: str = ""
    text: str = ""
    summary: str = ""

@app.post("/tools/memory/recall", summary="Recall past call memories for a person")
def tool_memory_recall(req: MemoryRecallRequest):
    """전화번호/이름으로 과거 통화 기억을 검색합니다."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/memory/recall",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json=req.dict(), timeout=10
        )
        return r.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/tools/memory/save", summary="Manually save a call memory")
def tool_memory_save(req: MemorySaveRequest, _net: bool = Depends(require_internal_network)):
    """통화 기억을 수동으로 저장합니다."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/memory/save",
            headers={"X-API-Secret": API_SECRET, "Content-Type": "application/json"},
            json=req.dict(), timeout=10
        )
        return r.json()
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

class ContactSearchQuery(BaseModel):
    query: str
    top_k: int = 3

@app.post("/tools/contacts/search", summary="Semantic search contacts via Qdrant")
def tool_search_contacts(req: ContactSearchQuery):
    """Qdrant 의미 검색으로 연락처 찾기 — '가족', '친구', '서울 지인' 등 자연어 검색 가능"""
    if not client:
        raise HTTPException(status_code=503, detail="Qdrant 미연결")
    try:
        query_vector = embed(req.query)
        hits = client.search(
            collection_name=CONTACTS_COLLECTION,
            query_vector=query_vector,
            limit=req.top_k,
            score_threshold=0.4
        )
        results = [
            {"name": h.payload.get("name",""), "number": h.payload.get("number",""), "score": round(h.score,3)}
            for h in hits
        ]
        return {"query": req.query, "results": results, "count": len(results)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class ContactRequest(BaseModel):
    name: str
    number: str = ""

@app.post("/tools/contacts/add", summary="Add contact")
def tool_add_contact(req: ContactRequest, _net: bool = Depends(require_internal_network)):
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
def tool_delete_contact(req: ContactRequest, _net: bool = Depends(require_internal_network)):
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
    report_to: str = ""

@app.post("/tools/schedule/add", summary="Add schedule")
def tool_add_schedule(req: ScheduleRequest, _net: bool = Depends(require_internal_network)):
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
                "message": req.message,
                "report_to": req.report_to
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
def tool_remove_schedule(req: ScheduleIdRequest, _net: bool = Depends(require_internal_network)):
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
def tool_toggle_schedule(req: ScheduleIdRequest, _net: bool = Depends(require_internal_network)):
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


# ════════════════════════════════════════════
# 📼 통화 녹음 ON/OFF 토글 Tool
# ════════════════════════════════════════════
class ToggleRequest(BaseModel):
    enable: bool = True

@app.post("/tools/recording/toggle", summary="Toggle call recording ON/OFF")
def tool_toggle_recording(req: ToggleRequest = None, _net: bool = Depends(require_internal_network)):
    """통화 녹음을 켜거나 끕니다. AI가 '녹음 켜줘' 또는 '녹음 꺼줘'로 제어합니다."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/toggle/recording",
            headers={"X-API-Secret": API_SECRET},
            timeout=10
        )
        data = r.json()
        enabled = data.get("enabled", False)
        status = "활성화 ✅" if enabled else "비활성화 ⭐"
        return {"status": "success", "message": f"📼 통화 녹음이 {status}되었습니다.", "enabled": enabled}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ════════════════════════════════════════════
# 📄 PDF 보고서 ON/OFF 토글 Tool
# ════════════════════════════════════════════
@app.post("/tools/pdf-report/toggle", summary="Toggle PDF report generation ON/OFF")
def tool_toggle_pdf(req: ToggleRequest = None, _net: bool = Depends(require_internal_network)):
    """PDF 통화 보고서 자동 생성을 켜거나 끕니다. AI가 'PDF 켜줘' 또는 'PDF 꺼줘'로 제어합니다."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.post(
            f"{TWILIO_BOT_URL}/toggle/pdf-report",
            headers={"X-API-Secret": API_SECRET},
            timeout=10
        )
        data = r.json()
        enabled = data.get("enabled", False)
        status = "활성화 ✅" if enabled else "비활성화 ⭐"
        return {"status": "success", "message": f"📄 PDF 보고서가 {status}되었습니다.", "enabled": enabled}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ════════════════════════════════════════════
# 📋 녹음/PDF 파일 목록 조회 Tool
# ════════════════════════════════════════════
@app.get("/tools/recordings", summary="List saved call recordings (MP3)")
def tool_list_recordings():
    """저장된 통화 녹음 파일(MP3) 목록을 보여줍니다. AI가 '녹음 목록 보여줘'로 조회합니다."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.get(
            f"{TWILIO_BOT_URL}/recordings",
            headers={"X-API-Secret": API_SECRET},
            timeout=10
        )
        data = r.json()
        count = data.get("count", 0)
        enabled = data.get("enabled", False)
        files = data.get("recordings", [])
        if count == 0:
            return {"message": f"📼 저장된 녹음 파일이 없습니다. (녹음 기능: {'켜짐' if enabled else '꺼짐'})", "count": 0}
        file_list = "\n".join([f"• {f['filename']} ({f['size_mb']}MB, {f['created']})" for f in files[:10]])
        return {
            "message": f"📼 녹음 파일 {count}개 (녹음 기능: {'켜짐' if enabled else '꺼짐'})\n\n{file_list}",
            "count": count,
            "recordings": files[:10]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/tools/reports", summary="List saved PDF call reports")
def tool_list_reports():
    """저장된 PDF 통화 보고서 목록을 보여줍니다. AI가 'PDF 목록 보여줘'로 조회합니다."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.get(
            f"{TWILIO_BOT_URL}/reports",
            headers={"X-API-Secret": API_SECRET},
            timeout=10
        )
        data = r.json()
        count = data.get("count", 0)
        enabled = data.get("enabled", False)
        files = data.get("reports", [])
        if count == 0:
            return {"message": f"📄 저장된 PDF 보고서가 없습니다. (PDF 기능: {'켜짐' if enabled else '꺼짐'})", "count": 0}
        file_list = "\n".join([f"• {f['filename']} ({f['size_kb']}KB, {f['created']})" for f in files[:10]])
        return {
            "message": f"📄 PDF 보고서 {count}개 (PDF 기능: {'켜짐' if enabled else '꺼짐'})\n\n{file_list}",
            "count": count,
            "reports": files[:10]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/tools/feature-status", summary="Check recording & PDF feature status")
def tool_feature_status():
    """녹음/PDF 기능 상태와 저장된 파일 수를 확인합니다."""
    if not API_SECRET:
        raise HTTPException(status_code=500, detail="API_SECRET 미설정")
    try:
        r = http_requests.get(
            f"{TWILIO_BOT_URL}/toggle/status",
            headers={"X-API-Secret": API_SECRET},
            timeout=10
        )
        data = r.json()
        rec = data.get("call_recording", {})
        pdf = data.get("pdf_report", {})
        rec_status = "켜짐 ✅" if rec.get("enabled") else "꺼짐 ⭐"
        pdf_status = "켜짐 ✅" if pdf.get("enabled") else "꺼짐 ⭐"
        return {
            "message": f"📼 통화 녹음: {rec_status} (파일 {rec.get('files', 0)}개)\n📄 PDF 보고서: {pdf_status} (파일 {pdf.get('files', 0)}개)",
            "call_recording": rec,
            "pdf_report": pdf
        }
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
        "version": "1.4.0",
        "features": ["RAG (Unified Search - PDF/TXT/CSV/DOCX)", "Phone Call Integration", "SMS Bidirectional Communication", "Call Recording (MP3)", "PDF Call Reports"],
        "endpoints": {
            "docs": "/docs",
            "openapi": "/openapi.json",
            "rag_upload": "/documents/upload",
            "rag_search": "/rag/search",
            "rag_list": "/documents/list",
            "phone_call_me": "/tools/call-me",
            "phone_call_contact": "/tools/call-contact",
            "phone_contacts": "/tools/contacts",
            "sms_send": "/tools/send-sms",
            "recording_toggle": "/tools/recording/toggle",
            "pdf_toggle": "/tools/pdf-report/toggle",
            "recordings_list": "/tools/recordings",
            "reports_list": "/tools/reports",
            "feature_status": "/tools/feature-status",
            "media_list": "/media",
            "media_file": "/media/{filename}",
            "media_upload": "/media/upload",
            "media_upload_page": "/upload",
            "health": "/health"
        }
    }

# ── 📷 미디어 파일 서빙 (사진/동영상/음성/PDF) ──────────────
MEDIA_DIR = "/app/media"

@app.get("/media", summary="List media files")
def list_media(folder: str = ""):
    """미디어 파일 목록 조회 (사진/동영상/음성/PDF)"""
    import re
    _media_root = os.path.realpath(MEDIA_DIR)
    target_dir = os.path.join(MEDIA_DIR, folder) if folder else MEDIA_DIR
    # Path Traversal 방어
    target_dir = os.path.realpath(target_dir)
    if target_dir != _media_root and not target_dir.startswith(_media_root + os.sep):
        raise HTTPException(status_code=403, detail="접근 거부")
    if not os.path.isdir(target_dir):
        return {"files": [], "folders": [], "total": 0}
    items = sorted(os.listdir(target_dir))
    files = []
    folders = []
    for item in items:
        full_path = os.path.join(target_dir, item)
        if os.path.isdir(full_path):
            folders.append(item)
        else:
            size = os.path.getsize(full_path)
            ext = os.path.splitext(item)[1].lower()
            file_type = "unknown"
            if ext in [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"]:
                file_type = "image"
            elif ext in [".mp4", ".webm", ".mov", ".avi", ".mkv"]:
                file_type = "video"
            elif ext in [".mp3", ".wav", ".ogg", ".m4a"]:
                file_type = "audio"
            elif ext == ".pdf":
                file_type = "pdf"
            elif ext in [".txt", ".md", ".csv", ".json", ".log"]:
                file_type = "text"
            files.append({"name": item, "size": size, "type": file_type})
    return {"files": files, "folders": folders, "total": len(files)}

@app.get("/media/{file_path:path}", summary="Serve media file")
def serve_media(file_path: str):
    """미디어 파일 다운로드/브라우저 표시"""
    import re, mimetypes
    # 보안: Path Traversal 방어
    _media_root = os.path.realpath(MEDIA_DIR)
    safe_path = os.path.realpath(os.path.join(MEDIA_DIR, file_path))
    if safe_path != _media_root and not safe_path.startswith(_media_root + os.sep):
        raise HTTPException(status_code=403, detail="접근 거부")
    if not os.path.isfile(safe_path):
        raise HTTPException(status_code=404, detail="파일 없음")
    mime_type, _ = mimetypes.guess_type(safe_path)
    return FileResponse(safe_path, media_type=mime_type or "application/octet-stream")

@app.post("/media/upload", summary="Upload media file")
async def upload_media(file: UploadFile = File(...), folder: str = ""):
    """미디어 파일 업로드 (사진/동영상/음성 등)"""
    import re
    _media_root = os.path.realpath(MEDIA_DIR)
    # 파일명 보안 검증
    filename = file.filename or "unnamed"
    filename = re.sub(r'[^\w가-힣._-]', '_', filename)
    if len(filename) > 100:
        filename = filename[:100]
    # 폴더 보안 검증
    if folder:
        folder = re.sub(r'[^\w가-힣/_-]', '_', folder)
        target_dir = os.path.realpath(os.path.join(MEDIA_DIR, folder))
        if target_dir != _media_root and not target_dir.startswith(_media_root + os.sep):
            raise HTTPException(status_code=403, detail="접근 거부")
        os.makedirs(target_dir, exist_ok=True)
        save_path = os.path.join(target_dir, filename)
    else:
        save_path = os.path.join(MEDIA_DIR, filename)
    # ── 보안: 업로드 크기 제한 (DoS 완화) ──
    content = await file.read()
    if len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail=f"파일이 너무 큽니다 (최대 {MAX_UPLOAD_BYTES // (1024*1024)}MB)")
    with open(save_path, "wb") as f:
        f.write(content)
    rel_path = os.path.relpath(save_path, MEDIA_DIR)
    size_kb = len(content) / 1024
    print(f"📷 미디어 업로드: {rel_path} ({size_kb:.0f}KB)")
    return {"status": "saved", "filename": filename, "path": rel_path, "size": len(content), "url": f"/media/{rel_path}"}

# ── 📷 미디어 업로드 페이지 (3중 보안: Docker 127.0.0.1 + Nginx deny all + IP 검증) ──
@app.get("/upload", response_class=HTMLResponse, summary="Media upload page")
def upload_page(request: Request):
    """미디어 업로드 웹 페이지 (로컬 전용 — 3중 보안)"""
    # 🔒 보안: CF Tunnel 외부 접근 차단
    if request.headers.get("CF-Connecting-IP") or request.headers.get("X-Forwarded-For"):
        return HTMLResponse("Access denied", status_code=403)
    # 🔒 보안: 로컬 IP + Docker 내부 네트워크만 허용 (정확한 사설망 판별)
    client_ip = request.client.host if request.client else ""
    is_local = _is_private_ip(client_ip)
    if not is_local:
        return HTMLResponse("Access denied", status_code=403)
    return HTMLResponse(UPLOAD_PAGE_HTML)

UPLOAD_PAGE_HTML = '''<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>미디어 업로드</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',sans-serif;background:#0a0a0f;color:#e8e6e3;min-height:100vh;display:flex;flex-direction:column;align-items:center;padding:2rem}
h1{font-size:1.5rem;margin-bottom:.5rem}
.sub{color:#9d9bab;font-size:.85rem;margin-bottom:1.5rem}
.drop-zone{width:100%;max-width:600px;border:2px dashed #444;border-radius:12px;padding:3rem 2rem;text-align:center;cursor:pointer;transition:all .3s}
.drop-zone:hover,.drop-zone.drag-over{border-color:#a29bfe;background:rgba(162,155,254,.08)}
.drop-zone .icon{font-size:3rem;margin-bottom:1rem}
.drop-zone p{color:#9d9bab;font-size:.9rem}
.folder-input{margin:1rem 0;display:flex;gap:.5rem;max-width:600px;width:100%}
.folder-input input{flex:1;background:#1a1a26;border:1px solid #2d2d44;border-radius:6px;color:#e8e6e3;padding:.5rem .8rem;font-size:.85rem}
.folder-input input::placeholder{color:#666}
.file-list{width:100%;max-width:600px;margin-top:1.5rem}
.file-item{display:flex;justify-content:space-between;align-items:center;background:#111119;border:1px solid #2d2d44;border-radius:6px;padding:.6rem 1rem;margin:.4rem 0;font-size:.85rem}
.file-item .name{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.file-item .status{margin-left:.5rem;font-size:.8rem}
.file-item .status.ok{color:#2ed573}
.file-item .status.err{color:#ff4757}
.file-item .status.uploading{color:#ffa502}
.file-item a{color:#70a1ff;text-decoration:none}
.file-item a:hover{text-decoration:underline}
input[type=file]{display:none}
.footer{margin-top:2rem;color:#555;font-size:.75rem}
</style>
</head>
<body>
<h1>📷 미디어 업로드</h1>
<p class="sub">사진, 동영상, 음성, PDF 파일을 드래그앤드롭으로 업로드합니다</p>
<div class="folder-input">
  <input type="text" id="folder" placeholder="폴더명 (예: photos/홍길동) — 비우면 최상위에 저장">
</div>
<div class="drop-zone" id="dropZone">
  <div class="icon">📁</div>
  <p>파일을 여기에 드래그하거나 클릭해서 선택</p>
  <input type="file" id="fileInput" multiple>
</div>
<div class="file-list" id="fileList"></div>
<p class="footer">🔒 로컬 전용 (외부 접근 차단) · 파일 크기 제한 없음</p>
<script>
const dropZone=document.getElementById("dropZone"),fileInput=document.getElementById("fileInput"),fileList=document.getElementById("fileList"),folderInput=document.getElementById("folder");
dropZone.addEventListener("click",()=>fileInput.click());
dropZone.addEventListener("dragover",e=>{e.preventDefault();dropZone.classList.add("drag-over")});
dropZone.addEventListener("dragleave",()=>dropZone.classList.remove("drag-over"));
dropZone.addEventListener("drop",e=>{e.preventDefault();dropZone.classList.remove("drag-over");handleFiles(e.dataTransfer.files)});
fileInput.addEventListener("change",e=>handleFiles(e.target.files));
function handleFiles(files){
  Array.from(files).forEach(file=>{
    const item=document.createElement("div");
    item.className="file-item";
    item.innerHTML=\`<span class="name">\${file.name} (\${(file.size/1024).toFixed(0)}KB)</span><span class="status uploading">업로드 중...</span>\`;
    fileList.prepend(item);
    const fd=new FormData();
    fd.append("file",file);
    const folder=folderInput.value.trim();
    const url=folder?"/media/upload?folder="+encodeURIComponent(folder):"/media/upload";
    fetch(url,{method:"POST",body:fd}).then(r=>r.json()).then(data=>{
      if(data.status==="saved"){
        item.innerHTML=\`<a href="/media/\${data.path}" target="_blank" class="name">✅ \${data.path} (\${(data.size/1024).toFixed(0)}KB)</a><span class="status ok">완료</span>\`;
      }else{
        item.querySelector(".status").textContent="오류";
        item.querySelector(".status").className="status err";
      }
    }).catch(()=>{
      item.querySelector(".status").textContent="실패";
      item.querySelector(".status").className="status err";
    });
  });
}
</script>
</body>
</html>'''

EOF

cat > tools-api/Dockerfile <<'EOF'
FROM python:3.11-slim
RUN groupadd -r -g 1002 apiuser && useradd -r -g apiuser -u 1002 -m -s /sbin/nologin apiuser
WORKDIR /app
RUN apt-get update && apt-get install -y gcc curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
RUN mkdir -p /app/data && chown -R apiuser:apiuser /app
EXPOSE 8000
USER apiuser
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

############################################
# 12. docker-compose.yml (동일)
############################################
SECRET_KEY=$(openssl rand -hex 32)
OPENWEBUI_API_KEY_PLACEHOLDER=""

cat > docker-compose.yml <<EOF
services:
  # 🆕 Socket.IO 멀티 워커 공유 백엔드
  #    UVICORN_WORKERS 가 2 이상이면 필수. 없으면 응답이 실시간으로 표시되지
  #    않고 새로고침(F5) 해야 보이는 증상이 발생한다.
  #    (워커 A 에 붙은 웹소켓으로 워커 B 가 만든 토큰을 보낼 수 없기 때문)
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      # redis:7-alpine 은 시작 시 root→redis 로 권한을 낮추며(setpriv) setuid/setgid 가 필요하다.
      # cap_drop:ALL 만 두면 'setpriv: setresuid failed' 로 컨테이너가 죽으므로 이 셋만 되돌린다.
      # (SETPCAP 은 일부 커널/WSL 환경에서 setpriv 의 ambient-cap 처리에 필요)
      - SETUID
      - SETGID
      - SETPCAP
    deploy:
      resources:
        limits:
          memory: 128M

  qdrant:
    image: qdrant/qdrant:latest
    volumes:
      - qdrant-data:/qdrant/storage
    ports:
      - "127.0.0.1:6333:6333"
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          memory: ${MEMORY_QDRANT}

  openapi-tools:
    build: ./tools-api
    env_file: .env
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    environment:
      - API_SECRET=${API_SECRET}
      - TWILIO_BOT_URL=http://twilio-bot:5000
      - RAG_UNIFIED_SEARCH=${RAG_UNIFIED_SEARCH}
      - MAX_UPLOAD_MB=50
      - TZ=Asia/Seoul
    volumes:
      - ./tools-api/data:/app/data
      - ~/ai-share:/app/media
      - ./twilio-bot/data/recordings:/app/media/recordings:ro
      - ./twilio-bot/data/reports:/app/media/reports:ro
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
      # 🆕 멀티 워커 — 캘린더 도구의 self-call 데드락 방지 (단일 워커면 도구가
      #    자기 자신 API를 부를 때 워커가 막혀 15초 타임아웃 발생). 4개로 해결.
      - UVICORN_WORKERS=${UVICORN_WORKERS:-4}
      - TZ=Asia/Seoul
      - WEBUI_NAME=${WEBUI_CUSTOM_NAME}
      - WEBUI_URL=${SERVER_DOMAIN}
      - CORS_ALLOW_ORIGIN=${SERVER_DOMAIN};http://localhost:3000;http://127.0.0.1:3000
      - WEBUI_SESSION_COOKIE_SECURE=true
      - WEBUI_AUTH_COOKIE_SECURE=true
      - WEBUI_SESSION_COOKIE_SAME_SITE=lax
      - WEBUI_AUTH_COOKIE_SAME_SITE=lax
      - ENABLE_WEBSOCKET_SUPPORT=true
      # 🆕 워커 간 Socket.IO 세션 공유 (UVICORN_WORKERS 2 이상일 때 필수)
      - WEBSOCKET_MANAGER=redis
      - WEBSOCKET_REDIS_URL=redis://redis:6379/0
      # 🆕 네이티브 함수 호출 — 프롬프트 파싱보다 툴 인자 정확도가 높다
      - DEFAULT_FUNCTION_CALLING=native
      # 🆕 JWT 만료 (기존 -1 = 무기한은 토큰 유출 시 영구 악용 위험)
      - JWT_EXPIRES_IN=\${JWT_EXPIRES_IN:-7d}
      - VECTOR_DB=qdrant
      - QDRANT_URI=http://qdrant:6333
EOF

if [ "$USE_OLLAMA" = true ]; then
cat >> docker-compose.yml <<EOF
      - ENABLE_OLLAMA_API=true
      - OLLAMA_BASE_URL=http://${OLLAMA_HOST_IP}:11434
      - RAG_EMBEDDING_ENGINE=ollama
      - RAG_EMBEDDING_MODEL=${OLLAMA_EMBED_MODEL:-nomic-embed-text}
      - RAG_TOP_K=10
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
      - redis
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: ${MEMORY_WEBUI}

  twilio-bot:
    build: ./twilio-bot
    container_name: twilio-bot
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
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
      - QDRANT_URL=http://qdrant:6333
      - OLLAMA_BASE_URL=http://${OLLAMA_HOST_IP}:11434
      - OLLAMA_EMBED_MODEL=${OLLAMA_EMBED_MODEL:-nomic-embed-text}
      - EMBED_DIM=${EMBED_DIM:-768}
      - TELEGRAM_BOT_TOKEN=\${TELEGRAM_BOT_TOKEN:-}
      - TELEGRAM_CHAT_ID=\${TELEGRAM_CHAT_ID:-}
      - WHISPER_TELEGRAM_BOT_TOKEN=\${WHISPER_TELEGRAM_BOT_TOKEN:-}
      - WHISPER_TELEGRAM_CHAT_ID=\${WHISPER_TELEGRAM_CHAT_ID:-}
      - ENABLE_CALL_RECORDING=\${ENABLE_CALL_RECORDING:-false}
      - ENABLE_PDF_REPORT=\${ENABLE_PDF_REPORT:-false}
      - REALTIME_MODE=\${REALTIME_MODE:-false}
      - REALTIME_WSS_DOMAIN=\${REALTIME_WSS_DOMAIN:-}
      - REALTIME_STREAM_PATH=\${REALTIME_STREAM_PATH:-/twilio-stream}
      - PYTHONUNBUFFERED=1
      - TZ=Asia/Seoul
    ports:
      - "127.0.0.1:5000:5000"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - contacts-data:/app/data
      # 📅 캘린더 키 공유: open-webui-data 볼륨을 읽기전용 마운트
      # (재발 방지: 메인 compose에 직접 넣어 docker compose up 만으로도 항상 붙음)
      - open-webui-data:/owui-data:ro
    depends_on:
      - qdrant
      - openapi-tools
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: ${MEMORY_TWILIO}

  # 🎙️ 진짜 실시간 음성 서버 (Twilio Media Streams)
  realtime-voice:
    build: ./realtime-voice
    container_name: realtime-voice
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    environment:
      - API_SECRET=${API_SECRET}
      - TWILIO_BOT_URL=http://twilio-bot:5000
      - OPENAI_API_KEY=${GROQ_API_KEY}
      - MODEL=llama-3.3-70b-versatile
      # STT/TTS 기본값 (밸브에서 voice_config.json 으로 덮어씀)
      - STT_PROVIDER=\${STT_PROVIDER:-deepgram}
      - DEEPGRAM_API_KEY=\${DEEPGRAM_API_KEY:-}
      - STT_MODEL=\${STT_MODEL:-nova-2}
      - TTS_PROVIDER=\${TTS_PROVIDER:-elevenlabs}
      - ELEVENLABS_API_KEY=\${ELEVENLABS_API_KEY:-}
      - TTS_VOICE=\${TTS_VOICE:-21m00Tcm4TlvDq8ikWAM}
      - TTS_MODEL=\${TTS_MODEL:-eleven_flash_v2_5}
      - REALTIME_LANG=\${DEFAULT_LANG:-ko}
      - REALTIME_PORT=5001
      - DATA_DIR=/app/data
      - PYTHONUNBUFFERED=1
      - TZ=Asia/Seoul
    # voice_config.json / whispers.json 을 twilio-bot 과 공유
    volumes:
      - contacts-data:/app/data
    ports:
      - "127.0.0.1:5001:5001"
    depends_on:
      - twilio-bot
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 512M

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
    command: ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--timeout", "60", "--access-logfile", "-", "twilio_bot:app"]

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
mkdir -p ~/ai-share
# 🔒 공유 디렉토리 권한 일관성: 777(과도) 대신 setgid + 그룹 쓰기(2775)
# - browser-agent(uid 1001), openapi-tools(uid 1002) 등 서로 다른 uid 컨테이너가
#   생성한 파일이 디렉토리 그룹을 상속하도록 하여 권한 충돌(읽기/삭제 불가)을 방지
chmod 2775 ~/ai-share 2>/dev/null || chmod 775 ~/ai-share 2>/dev/null || true
# 기존에 777/잘못된 권한으로 만들어진 하위 파일도 그룹 접근 가능하도록 보정
find ~/ai-share -type d -exec chmod 2775 {} + 2>/dev/null || true
find ~/ai-share -type f -exec chmod 664 {} + 2>/dev/null || true
echo "   ✅ Docker Secrets Override 생성 완료"
echo "   📄 docker-compose.override.yml (자동 병합)"

############################################
# 12-2. .gitignore / .dockerignore 보안 파일 생성
############################################
cat > "$BASE_DIR/.gitignore" << 'GIEOF'
# ── 민감 정보 (절대 커밋 금지) ──
.env
secrets/
*.key
*.pem

# ── 로그 / 데이터 ──
*.log
logs/
twilio-bot/data/
tools-api/data/
*.json.bak

# ── Docker 빌드 캐시 ──
__pycache__/
*.pyc
node_modules/
GIEOF

cat > "$BASE_DIR/.dockerignore" << 'DIEOF'
.env
secrets/
.git
.gitignore
logs/
*.md
*.log
DIEOF

echo "   ✅ .gitignore + .dockerignore 생성 완료"


############################################
# 13. 실행
############################################

echo ""
echo "┌────────────────────────────────────────────┐"
echo "📦 Docker 이미지 다운로드 중..."
echo "   인터넷 속도에 따라 수분~수십분 소요될 수 있습니다."
echo "   완료될 때까지 기다려 주세요..."
echo "└────────────────────────────────────────────┘"

# ── 네트워크 끊김 대비: 이미지 다운로드 자동 재시도 ──────────────
# GitHub(ghcr.io) 등에서 큰 이미지를 받다가 connection timed out 이 나도
# 이미 받은 레이어는 캐시되므로, 끊긴 지점부터 이어받기를 반복 시도한다.
_PULL_MAX_RETRIES=20
_pull_ok=false
for _try in $(seq 1 $_PULL_MAX_RETRIES); do
  echo "   ⬇️  이미지 다운로드 시도 ${_try}/${_PULL_MAX_RETRIES}..."
  if docker compose pull; then
    _pull_ok=true
    break
  fi
  echo "   ⚠️  다운로드가 중단되었습니다(네트워크 문제일 수 있음). 8초 후 이어받기 재시도..."
  sleep 8
done

if [ "$_pull_ok" = true ]; then
  echo "   ✅ 이미지 다운로드 완료!"
else
  echo ""
  echo "   ❌ 이미지 다운로드가 ${_PULL_MAX_RETRIES}회 재시도에도 완료되지 않았습니다."
  echo "      네트워크(특히 ghcr.io / GitHub) 연결 문제일 가능성이 높습니다."
  echo ""
  echo "   💡 아래를 직접 실행해 이어받기를 계속하세요 (성공할 때까지 자동 반복):"
  echo "      cd $BASE_DIR"
  echo "      until docker compose pull; do echo '재시도...'; sleep 8; done"
  echo ""
  echo "   💡 그래도 계속 끊기면 DNS 변경이 도움이 됩니다:"
  echo "      sudo sh -c 'echo nameserver 1.1.1.1 > /etc/resolv.conf'"
  echo "      docker compose pull"
  echo ""
  echo "   ⏸️  다운로드가 끝나면 다음으로 설치를 이어가세요:"
  echo "      cd $BASE_DIR && docker compose up -d"
  echo ""
  echo "   (이미지가 일부만 받아졌어도 위 명령을 반복하면 나머지만 이어받습니다.)"
  exit 1
fi

echo ""
echo "🔨 Docker 이미지 빌드 중..."
# 빌드도 pip/apt 를 GitHub·PyPI 에서 받으므로 일시적 네트워크 오류에 대비해 재시도
_BUILD_MAX_RETRIES=5
_build_ok=false
for _btry in $(seq 1 $_BUILD_MAX_RETRIES); do
  echo "   🔧 빌드 시도 ${_btry}/${_BUILD_MAX_RETRIES}..."
  if docker compose build; then
    _build_ok=true
    break
  fi
  echo "   ⚠️  빌드 중 오류(네트워크 문제일 수 있음). 8초 후 재시도..."
  sleep 8
done
if [ "$_build_ok" = true ]; then
  echo "   ✅ 이미지 빌드 완료!"
else
  echo "   ❌ 이미지 빌드가 ${_BUILD_MAX_RETRIES}회 재시도에도 실패했습니다."
  echo "   💡 직접 재시도: cd $BASE_DIR && docker compose build && docker compose up -d"
  exit 1
fi

echo ""
echo "🚀 컨테이너 시작..."

# 호스트 디렉토리 권한 설정 (컨테이너 UID 1001과 일치)
# 호스트 디렉토리 권한 설정 (컨테이너 UID 1001과 일치)
chown -R 1001:1001 twilio-bot/data/ 2>/dev/null || \
    sudo chown -R 1001:1001 twilio-bot/data/ 2>/dev/null || \
    chmod -R 777 twilio-bot/data/ 2>/dev/null || true
mkdir -p twilio-bot/logs && chown -R 1001:1001 twilio-bot/logs/ 2>/dev/null || \
    sudo chown -R 1001:1001 twilio-bot/logs/ 2>/dev/null || \
    chmod -R 777 twilio-bot/logs/ 2>/dev/null || true

# secrets 권한 (컨테이너 UID 1001 읽기 가능)
chmod 644 secrets/* 2>/dev/null || true
chmod +x secrets/*.sh 2>/dev/null || true
chown -R 1001:1001 secrets/ 2>/dev/null || \
    sudo chown -R 1001:1001 secrets/ 2>/dev/null || true

docker compose up -d
echo "   ✅ 컨테이너 시작 완료!"

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
for i in $(seq 1 60); do
  if timeout 3 curl -s http://localhost:5000/health >/dev/null 2>&1; then
    echo "   ✅ Twilio 봇 준비 완료!"; break
  fi
  printf "   ⏳ 대기 중... %d/%d\r" $i 60
  sleep 5
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
# ── Twilio Webhook Rate Limiting (보안: 대량 요청 방어) ──
limit_req_zone \$binary_remote_addr zone=twilio_webhook:10m rate=10r/s;
limit_req_zone \$binary_remote_addr zone=api_zone:10m rate=5r/s;

server {
    listen 80;
    server_name _;

    # 🔒 보안 강화: 서버 버전 은폐 + 보안 응답 헤더 (클릭재킹·MIME스니핑·XSS 방어)
    server_tokens off;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-XSS-Protection "1; mode=block" always;
    # HSTS: HTTPS(TLS 종단이 이 nginx이거나 Cloudflare Full) 환경에서만 브라우저가 적용
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    # 업로드 크기 제한 (대용량 요청으로 인한 자원 고갈 방어)
    client_max_body_size 25m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # OpenWebUI API/WebSocket — 캐시 비활성화 (필수)
    location ~* ^/(api|ws|websocket|oauth|callback|login) {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_cache off;
        proxy_no_cache 1;
        proxy_cache_bypass 1;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # 🎙️ Twilio Media Streams WebSocket → realtime-voice (진짜 실시간)
    location /twilio-stream {
        proxy_pass http://127.0.0.1:5001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        # 통화 내내 연결 유지 (최대 1시간)
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location /voice {
        limit_req zone=twilio_webhook burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /verify-pin {
        limit_req zone=twilio_webhook burst=5 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /respond {
        limit_req zone=twilio_webhook burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /voice-out-simple {
        limit_req zone=twilio_webhook burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /voice-out-welfare {
        limit_req zone=twilio_webhook burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /respond-admin {
        limit_req zone=twilio_webhook burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /respond-out {
        limit_req zone=twilio_webhook burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    location /voice-report {
        limit_req zone=twilio_webhook burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
    }
    location /call-status {
        limit_req zone=twilio_webhook burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
    }
    location /call-me {
        limit_req zone=api_zone burst=10 nodelay;
        allow 127.0.0.1; deny all;  # 🔒 외부 접근 차단
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /call-contact {
        limit_req zone=api_zone burst=10 nodelay;
        allow 127.0.0.1; deny all;  # 🔒 외부 접근 차단 (Docker 내부만 허용)
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /contacts {
        limit_req zone=api_zone burst=10 nodelay;
        allow 127.0.0.1; deny all;  # 🔒 외부 접근 차단
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /send-sms {
        limit_req zone=api_zone burst=10 nodelay;
        allow 127.0.0.1; deny all;  # 🔒 외부 접근 차단
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /sms-incoming {
        limit_req zone=twilio_webhook burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
    }
    location /block {
        limit_req zone=api_zone burst=10 nodelay;
        allow 127.0.0.1; deny all;  # 🔒 외부 접근 차단
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    # 📼 녹음 콜백 (Twilio → 서버)
    location /recording-callback {
        limit_req zone=twilio_webhook burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 60s;
    }
    # 📼 녹음/📄 보고서/🔧 토글 API — 🔒 외부 접근 차단
    location /recordings {
        limit_req zone=api_zone burst=10 nodelay;
        allow 127.0.0.1; deny all;  # 🔒 외부 접근 차단
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /reports {
        limit_req zone=api_zone burst=10 nodelay;
        allow 127.0.0.1; deny all;  # 🔒 외부 접근 차단
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /toggle {
        limit_req zone=api_zone burst=10 nodelay;
        allow 127.0.0.1; deny all;  # 🔒 외부 접근 차단
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /health {
        proxy_pass http://127.0.0.1:5000;
    }
    # /dashboard, /api/call-history 외부 접근 차단
    location /dashboard {
        allow 127.0.0.1;
        deny all;
    }
    location /api/call-history {
        allow 127.0.0.1;
        deny all;
    }
    location /api/ {
        allow 127.0.0.1;
        deny all;
    }
}
NGINXEOF

# sites-enabled 에 직접 복사 (심링크 아님 — 수정 즉시 반영)
sudo cp "$NGINX_CONF" /etc/nginx/sites-enabled/twilio-bot
echo "   ✅ Nginx 설정 적용 완료"

if sudo nginx -t 2>/dev/null; then
  sudo systemctl reload nginx
  echo "   ✅ Nginx 설정 완료!"
else
  echo "   ⚠️  Nginx 설정 오류"
fi

############################################
# SSL/HTTPS 자동 설정 (Let's Encrypt)
############################################
# Cloudflare Tunnel 사용 시 SSL 불필요 (CF가 HTTPS 처리)
# localhost가 아닌 실제 도메인이 있고, CF Tunnel이 아닌 경우에만 SSL 설정
SSL_DOMAIN=$(echo "$SERVER_DOMAIN" | sed 's|https\?://||' | sed 's|/.*||')
if [ "$SSL_DOMAIN" != "localhost" ] && [ -n "$SSL_DOMAIN" ] && ! echo "$SSL_DOMAIN" | grep -qE "^(localhost|127\.|192\.168\.|10\.)"; then
  echo ""
  echo "┌────────────────────────────────────────────┐"
  echo "🔒 SSL/HTTPS 보안 설정"
  echo "└────────────────────────────────────────────┘"
  echo "   도메인: $SSL_DOMAIN"
  echo ""
  echo "   Cloudflare Tunnel을 사용하신다면 SSL 설정이 불필요합니다."
  echo "   직접 도메인을 연결한 경우, Let's Encrypt SSL을 자동 설치합니다."
  echo ""
  read -t 60 -p "   🔒 SSL 인증서를 자동 설치할까요? (y/N, 60초 내 Enter=건너뜀): " INSTALL_SSL || true
  INSTALL_SSL=$(echo "$INSTALL_SSL" | xargs | tr '[:upper:]' '[:lower:]')

  if [ "$INSTALL_SSL" = "y" ] || [ "$INSTALL_SSL" = "yes" ]; then
    echo "   📦 certbot 설치 중..."
    sudo apt install -y certbot python3-certbot-nginx > /dev/null 2>&1

    echo "   🔐 SSL 인증서 발급 중 (도메인: $SSL_DOMAIN)..."
    if sudo certbot --nginx -d "$SSL_DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect 2>/dev/null; then
      echo "   ✅ SSL 인증서 발급 + HTTPS 리다이렉트 설정 완료!"
      echo "   🔄 자동 갱신 테스트 중..."
      if sudo certbot renew --dry-run > /dev/null 2>&1; then
        echo "   ✅ 자동 갱신 설정 확인 완료 (90일마다 자동 갱신)"
      else
        echo "   ⚠️  자동 갱신 테스트 실패 — 수동으로 확인해주세요: sudo certbot renew --dry-run"
      fi
    else
      echo "   ⚠️  SSL 인증서 발급 실패"
      echo "   원인: 도메인 DNS가 이 서버를 가리키지 않거나, 포트 80이 외부에서 접근 불가"
      echo "   나중에 수동 설치: sudo certbot --nginx -d $SSL_DOMAIN"
    fi
  else
    echo "   ⭐️ SSL 설정 건너뜀 (나중에 설치: sudo certbot --nginx -d $SSL_DOMAIN)"
  fi
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
    except Exception: pass
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
    except Exception: pass
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
    except Exception: pass
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
    except Exception: pass
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

  CF_TUNNEL_TOKEN=$(read_secret "   🔑 Cloudflare Tunnel Token 입력 (300초 내): " 300)

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
      echo ""
      echo "   📞 [월 통화시간 제한 기능 사용 시] 아래도 설정하세요:"
      echo "   Twilio Console → Phone Numbers → 해당 번호 → Voice Configuration"
      echo "   'Call status changes' → Status Callback URL:"
      echo "   https://twilio.yourdomain.com/call-status  (HTTP POST)"
      echo "   → 관리자 수신전화 통화시간이 월 누적으로 집계되어 300분 초과 시 자동 차단됩니다."

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
# 📞 Twilio 번호 Webhook 자동 설정
#   Voice / SMS / Status Callback URL 을 Twilio API 로 자동 구성.
#   (SERVER_DOMAIN 이 공개 URL이고 Twilio 인증정보가 있을 때만 실행)
############################################
if [[ -n "$TWILIO_ACCOUNT_SID" && -n "$TWILIO_AUTH_TOKEN" && -n "$TWILIO_PHONE_NUMBER" \
      && "$SERVER_DOMAIN" =~ ^https:// ]]; then
  echo ""
  echo "📞 Twilio 번호 Webhook 자동 설정 중..."
  TWILIO_AUTOCONF_RESULT=$(python3 <<PYTWILIO 2>&1
import sys
try:
    from twilio.rest import Client
except ImportError:
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "twilio", "-q", "--break-system-packages"], check=False)
    from twilio.rest import Client

sid   = "${TWILIO_ACCOUNT_SID}"
token = "${TWILIO_AUTH_TOKEN}"
phone = "${TWILIO_PHONE_NUMBER}"
domain = "${SERVER_DOMAIN}".rstrip("/")

try:
    client = Client(sid, token)
    # 번호 SID 조회
    numbers = client.incoming_phone_numbers.list(phone_number=phone, limit=1)
    if not numbers:
        print(f"SKIP: Twilio 계정에서 번호 {phone} 을 찾지 못했습니다. 수동 설정이 필요합니다.")
        sys.exit(0)
    num_sid = numbers[0].sid
    # Voice / SMS / Status Callback 자동 설정
    client.incoming_phone_numbers(num_sid).update(
        voice_url=f"{domain}/voice",
        voice_method="POST",
        sms_url=f"{domain}/sms-incoming",
        sms_method="POST",
        status_callback=f"{domain}/call-status",
        status_callback_method="POST",
    )
    print("SUCCESS")
    print(f"  Voice:          {domain}/voice")
    print(f"  SMS:            {domain}/sms-incoming")
    print(f"  Status Callback:{domain}/call-status")
except Exception as e:
    print(f"FAIL: {e}")
PYTWILIO
)
  if echo "$TWILIO_AUTOCONF_RESULT" | grep -q "SUCCESS"; then
    echo "   ✅ Twilio Webhook 자동 설정 완료!"
    echo "$TWILIO_AUTOCONF_RESULT" | grep -E "Voice:|SMS:|Status" | while IFS= read -r line; do
      echo "   $line"
    done
    echo "   → 월 통화시간 제한이 자동으로 작동합니다 (Status Callback 설정됨)."
  else
    echo "   ⚠️  Twilio 자동 설정을 완료하지 못했습니다. 아래를 수동으로 설정하세요:"
    echo "$TWILIO_AUTOCONF_RESULT" | sed 's/^/      /'
    echo "      Twilio Console → Phone Numbers → 번호 선택 → Voice/Messaging Configuration"
    echo "      Voice URL:           ${SERVER_DOMAIN}/voice  (POST)"
    echo "      SMS URL:             ${SERVER_DOMAIN}/sms-incoming  (POST)"
    echo "      Status Callback URL: ${SERVER_DOMAIN}/call-status  (POST)"
  fi
else
  echo ""
  echo "📞 Twilio Webhook 수동 설정 안내 (자동 설정 조건 미충족):"
  echo "   Twilio Console → Phone Numbers → 번호 선택 → Configuration"
  echo "   Voice URL:           ${SERVER_DOMAIN}/voice  (POST)"
  echo "   SMS URL:             ${SERVER_DOMAIN}/sms-incoming  (POST)"
  echo "   Status Callback URL: ${SERVER_DOMAIN}/call-status  (POST)"
  echo "   → Status Callback 을 설정해야 월 통화시간 제한이 작동합니다."
fi


############################################
# OpenWebUI 계정 생성 + API 키 발급 + Tool 자동 등록
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔐 OpenWebUI 계정 생성 + Tool 자동 등록 중..."
echo "└────────────────────────────────────────────┘"

OW_READY=false
for i in $(seq 1 60); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null)
  if [ "$STATUS" = "200" ]; then
    OW_READY=true
    echo "   ✅ OpenWebUI 준비 완료!"
    break
  fi
  echo "   ⏳ OpenWebUI 대기 중... (${i}/60)"
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
import json, urllib.request, sys, time, os

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

    def call_contact(self, name: str, mission: str = "안부 확인", message: str = "", report_to: str = "") -> str:
        """저장된 연락처에게 전화를 걸어줍니다.

        Args:
            name: 연락처 이름 (예: 김철수)
            mission: AI가 수행할 임무 (예: 안부 확인, 회의 참석 여부 확인)
            message: 상대방에게 직접 전달할 말. 반드시 사용자가 전달하려는 문장을 그대로 넣으세요.
            report_to: 통화 결과를 보고받을 전화번호 (예: +821098765432). 비우면 관리자에게 보고.

        사용 예시:
            "김철수한테 안부전화 해줘. 어떻게 지내세요?" → name="김철수", mission="안부 확인", message="어떻게 지내세요?"
            "김철수한테 전화해줘. 결과는 01098765432로 보고해줘" → name="김철수", report_to="+821098765432"
            "김철수한테 전화해줘" → name="김철수", mission="안부 확인", message=""

        중요: 사용자가 마침표/쉼표 뒤에 전달할 말을 적었다면 message에 반드시 포함하세요. 비워두면 AI가 자동 생성합니다.
        """
        try:
            payload = {"name": name, "mission": mission, "message": message}
            if report_to:
                payload["report_to"] = report_to
            r = requests.post(f"{TOOL_SERVER}/tools/call-contact",
                            json=payload, timeout=10)
            return r.json().get("message", f"{name}님께 전화를 걸었습니다.")
        except Exception as e:
            return f"오류: {e}"

    def get_contacts(self, name: str = "", page: int = 1) -> str:
        """저장된 연락처 목록을 조회합니다. 이름을 지정하면 검색, 없으면 15개씩 페이지로 보여줍니다.

        사용 예시:
            "저장된 연락처 보여줘" → name="", page=1 (1페이지, 1~15번)
            "연락처 2페이지" / "다음 페이지" → page=2 (16~30번)
            "김철수 연락처" → name="김철수" (검색)
            "부산 친구 연락처" → name="부산" (검색)

        page: 몇 페이지를 볼지. 사용자가 "2페이지", "다음"이라고 하면 그 숫자를 넣으세요.
        """
        try:
            # page 안전 변환 (LLM이 문자열로 넘길 수 있음)
            try:
                page = int(page)
            except (ValueError, TypeError):
                page = 1
            if page < 1:
                page = 1

            r = requests.get(f"{TOOL_SERVER}/tools/contacts", timeout=10)
            data = r.json()
            contacts = data.get("contacts", {})
            if not contacts:
                return "저장된 연락처가 없습니다."

            # 이름 검색이 있으면 필터링 (검색은 페이지 없이 전부)
            if name:
                filtered = {k: v for k, v in contacts.items() if name.lower() in k.lower()}
                if not filtered:
                    return f"'{name}' 연락처를 찾을 수 없습니다. (총 {len(contacts)}명 저장됨)"
                result = f"'{name}' 검색 결과 ({len(filtered)}명):\\n"
                for n, number in filtered.items():
                    display = number.replace("+82", "0") if number.startswith("+82") else number
                    result += f"- {n}: {display}\\n"
                return result

            # 전체 목록: 15개씩 페이지네이션 (이름 가나다순 정렬)
            PER_PAGE = 15
            items = sorted(contacts.items(), key=lambda x: x[0])
            total = len(items)
            total_pages = (total + PER_PAGE - 1) // PER_PAGE
            if page > total_pages:
                page = total_pages

            start = (page - 1) * PER_PAGE
            end = start + PER_PAGE
            page_items = items[start:end]

            result = f"📇 저장된 연락처 (총 {total}명 · {page}/{total_pages}페이지)\\n\\n"
            for idx, (n, number) in enumerate(page_items, start=start + 1):
                display = number.replace("+82", "0") if number.startswith("+82") else number
                result += f"{idx}. {n}: {display}\\n"

            # 다음 페이지 안내
            if page < total_pages:
                result += f"\\n▶ 다음 15명을 보려면 \\"연락처 {page + 1}페이지\\" 또는 \\"다음 페이지\\"라고 입력하세요."
            else:
                result += "\\n(마지막 페이지입니다.)"
            return result
        except Exception as e:
            return f"오류: {e}"

    def update_contact(self, name: str, new_number: str = "", new_name: str = "") -> str:
        """저장된 연락처의 번호나 이름을 수정합니다.

        사용 예시:
            "박익제 번호를 010-9999-8888로 바꿔줘" → name="박익제", new_number="010-9999-8888"
            "박익제를 박익재로 이름 바꿔줘" → name="박익제", new_name="박익재"
            "박익제 이름은 박익재, 번호는 010-1111-2222로 수정" → name="박익제", new_name="박익재", new_number="010-1111-2222"

        name: 현재 저장된 이름(필수). new_number: 새 전화번호(선택). new_name: 새 이름(선택).
        """
        try:
            name = (name or "").strip()
            new_number = (new_number or "").strip()
            new_name = (new_name or "").strip()
            if not name:
                return "수정할 연락처 이름을 알려주세요."
            if not new_number and not new_name:
                return "바꿀 번호나 이름 중 하나는 알려주세요."

            # 1) 현재 연락처 조회
            r = requests.get(f"{TOOL_SERVER}/tools/contacts", timeout=10)
            contacts = r.json().get("contacts", {})
            if name not in contacts:
                return f"'{name}' 연락처를 찾을 수 없습니다. 정확한 이름을 확인해 주세요."

            cur_number = contacts[name]
            target_name = new_name if new_name else name
            target_number = new_number if new_number else cur_number

            # 2) 이름이 바뀌는 경우: 기존 이름 삭제
            if new_name and new_name != name:
                if new_name in contacts:
                    return f"'{new_name}' 이름이 이미 존재합니다. 다른 이름을 쓰거나 기존 것을 먼저 정리해 주세요."
                requests.post(f"{TOOL_SERVER}/tools/contacts/delete",
                              json={"name": name, "number": ""}, timeout=10)

            # 3) 새 정보로 저장 (add 가 같은 이름이면 덮어쓰기)
            ra = requests.post(f"{TOOL_SERVER}/tools/contacts/add",
                               json={"name": target_name, "number": target_number}, timeout=10)
            if ra.status_code != 200:
                return f"수정 실패: {ra.text}"

            disp = target_number.replace("+82", "0") if target_number.startswith("+82") else target_number
            changed = []
            if new_name and new_name != name:
                changed.append(f"이름 {name} → {target_name}")
            if new_number:
                changed.append(f"번호 → {disp}")
            return f"연락처를 수정했습니다. ({', '.join(changed)})"
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
            # LLM이 문자열로 전달할 수 있으므로 강제 변환
            try:
                limit = int(limit)
            except (ValueError, TypeError):
                limit = 10
            if limit < 1 or limit > 200:
                limit = 10

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
description: 업로드된 문서에서 정보 검색 및 문서 목록 조회
version: 1.1.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def search_documents(self, query: str, top_k: int = 3) -> str:
        """업로드된 문서에서 관련 정보를 검색합니다."""
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

    def list_documents(self) -> str:
        """전화용 RAG에 업로드된 문서 목록을 조회합니다."""
        try:
            r = requests.get(
                f"{TOOL_SERVER}/documents/list",
                timeout=10
            )
            data = r.json()
            files = data.get("files", [])
            total_vectors = data.get("total_vectors", 0)
            
            if not files:
                return "업로드된 문서가 없습니다."
            
            response = f"📚 전화용 RAG 문서 목록 ({len(files)}개, 벡터 {total_vectors}개):\\n\\n"
            for i, f in enumerate(files, 1):
                response += f"  {i}. {f['filename']} ({f['size_kb']}KB)\\n"
            
            return response
        except Exception as e:
            return f"문서 목록 조회 오류: {e}"
'''

sms_tool_code = '''\
"""
title: SMS 보내기
author: SMS Tool
description: 지정한 번호 또는 연락처 이름으로 SMS를 보냅니다 (답장 자동 전달)
version: 1.3.0
"""
import re
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def send_sms(self, phone_number: str, message: str) -> str:
        """SMS를 보냅니다. 상대방이 답장하면 자동으로 관리자에게 전달됩니다.

        phone_number에는 전화번호 또는 저장된 연락처 이름을 넣을 수 있습니다.
        이름이 들어오면 연락처에서 실제 번호를 조회합니다.

        사용 예시:
            "박익제한테 문자 보내줘: 오늘 날씨가 덥네" → phone_number="박익제", message="오늘 날씨가 덥네"
            "010-1234-5678로 문자 보내줘" → phone_number="01012345678", message="..."

        중요: 번호를 임의로 생성하거나 추측하지 마세요.
        이름만 알고 번호를 모르면 이름을 그대로 넣으면 서버가 조회합니다.
        """
        try:
            raw = (phone_number or "").strip()
            if not raw:
                return "수신자(이름 또는 전화번호)가 비어 있습니다."

            # 번호처럼 보이는지 검사 (+, 숫자, 하이픈, 공백만 있으면 번호로 간주)
            is_number = bool(re.fullmatch(r"[+\d][\d\s\-]*", raw))

            if is_number:
                # 번호 → E.164 정규화
                number = raw.replace("-", "").replace(" ", "")
                if number.startswith("0"):
                    number = "+82" + number[1:]
                elif not number.startswith("+"):
                    number = "+82" + number
            else:
                # 이름 → 연락처 조회
                number = self._lookup_contact(raw)
                if not number:
                    return f"'{raw}' 연락처를 찾을 수 없습니다. 전화번호를 확인해 주세요."

            # 최종 형식 검증 (E.164: +로 시작, 8~15자리 숫자)
            if not re.fullmatch(r"\+\d{8,15}", number):
                return f"유효하지 않은 전화번호 형식입니다: {number}"

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

    def _lookup_contact(self, name: str) -> str:
        """이름으로 연락처의 실제 전화번호를 조회한다. 없으면 빈 문자열."""
        try:
            r = requests.get(f"{TOOL_SERVER}/tools/contacts", timeout=10)
            if r.status_code != 200:
                return ""
            contacts = r.json().get("contacts", {})  # {이름: 번호} 딕셔너리
            target = name.strip()

            # 1) 정확히 일치
            if target in contacts:
                return str(contacts[target]).strip()

            # 2) 공백 제거 후 일치 (예: "박 익제" → "박익제")
            compact = target.replace(" ", "")
            for cname, cnum in contacts.items():
                if cname.replace(" ", "") == compact:
                    return str(cnum).strip()

            return ""
        except Exception:
            return ""
'''

def register_tool(tool_id, tool_name, tool_desc, tool_code):
    payload = {
        "id": tool_id,
        "name": tool_name,
        "description": tool_desc,
        "content": tool_code,
        "meta": {"description": tool_desc, "manifest": {}}
    }
    data = json.dumps(payload).encode()
    headers = {"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"}
    
    for attempt in range(3):
        # 1차: CREATE 시도
        req = urllib.request.Request(
            "http://localhost:3000/api/v1/tools/create",
            data=data, headers=headers, method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                d = json.loads(resp.read())
                return f"SUCCESS: {d.get('name', tool_name)}"
        except urllib.error.HTTPError as e:
            error_msg = e.read().decode()[:300]
            error_lower = error_msg.lower()
            if any(kw in error_lower for kw in ["already registered", "already exists", "unique constraint", "duplicate", "conflict"]):
                # 2차: 이미 존재하면 DELETE → CREATE (완전 재등록)
                try:
                    del_req = urllib.request.Request(
                        f"http://localhost:3000/api/v1/tools/id/{tool_id}/delete",
                        headers=headers, method="DELETE"
                    )
                    urllib.request.urlopen(del_req, timeout=10)
                    time.sleep(1)
                    # 삭제 후 다시 CREATE
                    req3 = urllib.request.Request(
                        "http://localhost:3000/api/v1/tools/create",
                        data=data, headers=headers, method="POST"
                    )
                    with urllib.request.urlopen(req3, timeout=30) as resp3:
                        d3 = json.loads(resp3.read())
                        return f"RECREATED: {d3.get('name', tool_name)} (삭제 후 재등록)"
                except Exception as e2:
                    # DELETE 실패 시 UPDATE 시도
                    try:
                        req4 = urllib.request.Request(
                            f"http://localhost:3000/api/v1/tools/id/{tool_id}/update",
                            data=data, headers=headers, method="POST"
                        )
                        with urllib.request.urlopen(req4, timeout=30) as resp4:
                            d4 = json.loads(resp4.read())
                            return f"UPDATED: {d4.get('name', tool_name)}"
                    except Exception as e3:
                        pass
            if attempt < 2:
                print(f"  ⚠️ {tool_name} 등록 재시도 ({attempt+2}/3)...")
                time.sleep(3)
            else:
                return f"FAIL: {tool_name} - {error_msg}"
        except Exception as e:
            if attempt < 2:
                print(f"  ⚠️ {tool_name} 연결 재시도 ({attempt+2}/3)...")
                time.sleep(3)
            else:
                return f"ERROR: {tool_name} - {str(e)}"
    return f"FAIL: {tool_name} - 3회 재시도 실패"

print("1️⃣  전화 어시스턴트 Tool 등록 중...")
result1 = register_tool("phone_assistant_v2", "전화 어시스턴트", "전화 걸기, 안부전화(사용자 메시지 직접 전달 가능), 연락처 저장/수정/삭제/조회(15개씩 페이지), 통화 기록 조회", phone_tool_code)
print(result1)
time.sleep(1)

print("2️⃣  RAG 문서 검색 Tool 등록 중...")
result2 = register_tool("rag_document_search", "RAG 문서 검색", "업로드된 문서에서 정보 검색 및 문서 목록 조회", rag_tool_code)
print(result2)
time.sleep(1)

print("3️⃣  SMS 보내기 Tool 등록 중...")
result3 = register_tool("sms_sender", "SMS 보내기", "지정한 번호로 SMS를 보냅니다 (답장 자동 전달)", sms_tool_code)
print(result3)
time.sleep(1)

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
    def add_schedule(self, contact_name: str, action: str = "call", schedule_time: str = "", repeat: str = "", mission: str = "안부 확인", message: str = "", report_to: str = "") -> str:
        """전화 또는 SMS 예약을 등록합니다.

        Args:
            contact_name: 연락처 이름 (예: 김철수)
            action: "call" (전화) 또는 "sms" (문자)
            schedule_time: 1회 예약은 "2025-03-25 15:00", 반복은 "15:00" (시간만)
            repeat: 빈값(1회), "daily"(매일), "weekly:월"(매주 월요일), "monthly:15"(매월 15일)
            mission: AI가 수행할 임무 (예: 안부 확인, 회의 참석 확인)
            message: 전달할 메시지
            report_to: 결과 보고받을 전화번호 (예: +821098765432). 비우면 관리자에게 보고.

        사용 예시:
            "내일 오후 3시에 김철수한테 전화해줘" → schedule_time="2025-03-26 15:00", repeat=""
            "매주 월요일 10시에 김철수한테 안부전화 해줘" → schedule_time="10:00", repeat="weekly:월"
            "매일 아침 9시에 김철수한테 전화해줘. 결과는 01098765432로 보고해줘" → report_to="+821098765432"
        """
        try:
            payload = {"contact_name": contact_name, "action": action,
                       "schedule_time": schedule_time, "repeat": repeat,
                       "mission": mission, "message": message}
            if report_to:
                payload["report_to"] = report_to
            r = requests.post(f"{TOOL_SERVER}/tools/schedule/add",
                            json=payload, timeout=10)
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

# ═══ 5. 통화 녹음 관리 Tool ═══
recording_tool_code = '''\
"""
title: 통화 녹음 관리
author: Recording Tool
description: 통화 녹음 ON/OFF 전환, 녹음 파일 목록 조회
version: 1.0.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def toggle_recording(self) -> str:
        """통화 녹음을 켜거나 끕니다. 현재 상태의 반대로 전환됩니다."""
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/recording/toggle", timeout=10)
            if r.status_code == 200:
                return r.json().get("message", "녹음 토글 완료")
            return f"오류: {r.text}"
        except Exception as e:
            return f"오류: {e}"

    def list_recordings(self) -> str:
        """저장된 통화 녹음 파일(MP3) 목록을 보여줍니다."""
        try:
            r = requests.get(f"{TOOL_SERVER}/tools/recordings", timeout=10)
            if r.status_code == 200:
                return r.json().get("message", "녹음 목록 조회 완료")
            return f"오류: {r.text}"
        except Exception as e:
            return f"오류: {e}"
'''

print("5️⃣  통화 녹음 관리 Tool 등록 중...")
result5 = register_tool("recording_manager", "통화 녹음 관리", "통화 녹음 ON/OFF 전환, 녹음 파일(MP3) 목록 조회", recording_tool_code)
print(result5)

# ═══ 6. PDF 보고서 관리 Tool ═══
pdf_tool_code = '''\
"""
title: PDF 보고서 관리
author: PDF Report Tool
description: PDF 통화 보고서 ON/OFF 전환, 보고서 목록 조회
version: 1.0.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def toggle_pdf_report(self) -> str:
        """PDF 통화 보고서 자동 생성을 켜거나 끕니다. 현재 상태의 반대로 전환됩니다."""
        try:
            r = requests.post(f"{TOOL_SERVER}/tools/pdf-report/toggle", timeout=10)
            if r.status_code == 200:
                return r.json().get("message", "PDF 토글 완료")
            return f"오류: {r.text}"
        except Exception as e:
            return f"오류: {e}"

    def list_reports(self) -> str:
        """저장된 PDF 통화 보고서 목록을 보여줍니다."""
        try:
            r = requests.get(f"{TOOL_SERVER}/tools/reports", timeout=10)
            if r.status_code == 200:
                return r.json().get("message", "PDF 목록 조회 완료")
            return f"오류: {r.text}"
        except Exception as e:
            return f"오류: {e}"
'''

print("6️⃣  PDF 보고서 관리 Tool 등록 중...")
result6 = register_tool("pdf_report_manager", "PDF 보고서 관리", "PDF 통화 보고서 ON/OFF 전환, 보고서 목록 조회", pdf_tool_code)
print(result6)

# ═══ 7. 녹음/PDF 기능 상태 확인 Tool ═══
feature_status_tool_code = '''\
"""
title: 기능 상태 확인
author: Feature Status Tool
description: 통화 녹음, PDF 보고서 기능의 현재 상태와 저장된 파일 수를 확인합니다
version: 1.0.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def check_feature_status(self) -> str:
        """녹음/PDF 기능 상태와 저장된 파일 수를 확인합니다."""
        try:
            r = requests.get(f"{TOOL_SERVER}/tools/feature-status", timeout=10)
            if r.status_code == 200:
                return r.json().get("message", "상태 확인 완료")
            return f"오류: {r.text}"
        except Exception as e:
            return f"오류: {e}"
'''

print("7️⃣  기능 상태 확인 Tool 등록 중...")
result7 = register_tool("feature_status", "기능 상태 확인", "통화 녹음/PDF 보고서 기능 상태 + 파일 수 확인", feature_status_tool_code)
print(result7)

# ── 8️⃣ 미디어 관리 Tool ──
media_tool_code = '''
"""
title: 미디어 관리
description: 사진/동영상/음성/PDF 파일 목록 조회 및 링크 제공. 녹음 파일, PDF 보고서도 조회 가능.
version: 1.0.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"
MEDIA_URL = "http://localhost:8000"

class Tools:
    def list_media(self, folder: str = "") -> str:
        """미디어 파일 목록을 조회합니다. folder: 하위 폴더 (예: photos/홍길동, recordings, reports). 비우면 전체 목록."""
        try:
            r = requests.get(f"{TOOL_SERVER}/media", params={"folder": folder}, timeout=10)
            if r.status_code != 200:
                return f"오류: {r.text}"
            data = r.json()
            if data["total"] == 0 and not data.get("folders"):
                return f"📁 {'/' + folder if folder else ''} 폴더에 파일이 없습니다."
            result = f"📁 {'/' + folder if folder else '/media'} ({data['total']}개 파일)\\n"
            for f in data.get("folders", []):
                result += f"  📂 {f}/\\n"
            for f in data.get("files", []):
                icon = {"image":"📷","video":"🎬","audio":"🎵","pdf":"📄","text":"📝"}.get(f["type"], "📎")
                size_kb = f["size"] / 1024
                path = f"{folder}/{f['name']}" if folder else f['name']
                link = f"{MEDIA_URL}/media/{path}"
                result += f"  {icon} [{f['name']}]({link}) ({size_kb:.0f}KB)\\n"
            return result
        except Exception as e:
            return f"오류: {e}"

    def list_recordings(self) -> str:
        """통화 녹음 파일(MP3) 목록을 조회합니다."""
        return self.list_media("recordings")

    def list_reports(self) -> str:
        """PDF 통화 보고서 목록을 조회합니다."""
        return self.list_media("reports")

    def upload_media(self, file_url: str, filename: str, folder: str = "") -> str:
        """채팅에서 첨부한 파일을 미디어 폴더에 저장합니다. file_url: 첨부파일 URL, filename: 저장할 파일명, folder: 하위 폴더 (예: photos/홍길동)"""
        try:
            # 첨부파일 다운로드
            file_resp = requests.get(file_url, timeout=30)
            if file_resp.status_code != 200:
                return f"파일 다운로드 실패: HTTP {file_resp.status_code}"
            # 업로드
            files = {"file": (filename, file_resp.content)}
            params = {"folder": folder} if folder else {}
            r = requests.post(f"{TOOL_SERVER}/media/upload", files=files, params=params, timeout=30)
            if r.status_code == 200:
                data = r.json()
                link = f"{MEDIA_URL}/media/{data['path']}"
                size_kb = data['size'] / 1024
                return f"📷 저장 완료: [{data['path']}]({link}) ({size_kb:.0f}KB)"
            return f"업로드 오류: {r.text}"
        except Exception as e:
            return f"오류: {e}"
'''

print("8️⃣  미디어 관리 Tool 등록 중...")
result8 = register_tool("media_manager", "미디어 관리", "사진/동영상/음성/PDF/녹음 파일 업로드, 목록 조회, 링크 제공", media_tool_code)
print(result8)

# ── 9️⃣ 캘린더 (오늘 일정) — 밸브에 API 키 입력 방식 / 제작자: webmaster@vulva.sex ──
calendar_tool_code = '''\
"""
title: 캘린더 (조회·등록)
author: webmaster@vulva.sex
description: OpenWebUI 캘린더에서 오늘/특정 날짜 일정을 조회하고 새 일정을 등록합니다. 밸브에 API 키 입력.
version: 1.1.0
"""
import datetime
import requests
from pydantic import BaseModel, Field


class Tools:
    class Valves(BaseModel):
        OPENWEBUI_API_KEY: str = Field(
            default="",
            description="OpenWebUI API 키 (설정>계정>API 키에서 발급, sk-...). 본인 캘린더 조회에 사용됩니다.",
        )
        OPENWEBUI_URL: str = Field(
            default="http://open-webui:8080",
            description="OpenWebUI 내부 주소 (보통 변경 불필요)",
        )
        ADMIN_ONLY: bool = Field(
            default=True,
            description="관리자만 사용 허용 (켜두는 것을 권장)",
        )
        TWILIO_BOT_URL: str = Field(
            default="http://twilio-bot:5000",
            description="전화 봇 내부 주소 (일정 알림을 전화·문자로 받으려면 필요. 보통 변경 불필요)",
        )
        TWILIO_BOT_SECRET: str = Field(
            default="",
            description="전화 봇 API Secret (.env 의 API_SECRET 값). 비우면 알림 전화·문자 예약을 건너뜁니다.",
        )
        ENABLE_CALL_SMS_REMINDER: bool = Field(
            default=True,
            description="일정 등록 시 알림 시각에 관리자에게 전화+문자 알림을 예약할지 여부",
        )

    def __init__(self):
        self.valves = self.Valves()

    def _resolve_key(self):
        """밸브 키를 가져오고, 전화 봇과 공유하도록 공유 폴더에 동기화한다."""
        key = (self.valves.OPENWEBUI_API_KEY or "").strip()
        if not key:
            return None
        try:
            import os as _os
            share_dir = "/app/backend/data/shared-key"
            _os.makedirs(share_dir, exist_ok=True)
            share_path = _os.path.join(share_dir, "openwebui_api_key")
            _prev = ""
            if _os.path.exists(share_path):
                with open(share_path, "r") as _f:
                    _prev = _f.read().strip()
            if _prev != key:
                with open(share_path, "w") as _f:
                    _f.write(key)
                try:
                    _os.chmod(share_dir, 0o755)
                    _os.chmod(share_path, 0o644)
                except Exception:
                    pass
        except Exception:
            pass
        return key

    def _check_admin(self, __user__):
        """ADMIN_ONLY 가 켜져 있으면 관리자만 허용. 통과 시 None, 아니면 안내문 반환."""
        if self.valves.ADMIN_ONLY:
            role = ""
            if isinstance(__user__, dict):
                role = (__user__.get("role") or "")
            if role != "admin":
                return "이 기능은 관리자만 사용할 수 있습니다."
        return None

    def _base_url(self):
        return (self.valves.OPENWEBUI_URL or "http://open-webui:8080").rstrip("/")

    def _get_events(self, key, start_iso, end_iso):
        """지정 범위의 이벤트 목록을 조회. (events_list, error_str) 반환."""
        try:
            _s = requests.Session()
            _s.trust_env = False
            r = _s.get(
                f"{self._base_url()}/api/v1/calendars/events",
                headers={"Authorization": f"Bearer {key}"},
                params={"start": start_iso, "end": end_iso},
                timeout=30, allow_redirects=False,
            )
        except Exception as e:
            return None, f"캘린더 서버 연결 실패: {e}"
        if r.status_code == 401:
            return None, "API 키 인증에 실패했습니다. 밸브의 키를 확인해 주세요."
        if r.status_code == 403:
            return None, "캘린더 접근 권한이 없습니다."
        if r.status_code >= 400:
            return None, f"일정 조회 실패 (HTTP {r.status_code})."
        try:
            return r.json(), None
        except Exception:
            return None, "일정 응답을 해석하지 못했습니다."

    def _get_default_calendar_id(self, key):
        """이벤트 생성에 필요한 기본 캘린더 id 를 조회 (없으면 None)."""
        try:
            _s = requests.Session()
            _s.trust_env = False
            r = _s.get(
                f"{self._base_url()}/api/v1/calendars/",
                headers={"Authorization": f"Bearer {key}"},
                timeout=30, allow_redirects=False,
            )
            if r.status_code >= 400:
                return None
            cals = r.json()
        except Exception:
            return None
        if not isinstance(cals, list) or not cals:
            return None
        real = [c for c in cals if c.get("id") != "__scheduled_tasks__"]
        if not real:
            return None
        for c in real:
            if c.get("is_default"):
                return c.get("id")
        return real[0].get("id")

    def _render(self, header, events):
        """이벤트 목록을 사람이 읽는 텍스트로 정리."""
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
            when = self._fmt(e.get("start_at"), e.get("all_day", False))
            title = e.get("title") or "(제목 없음)"
            loc = e.get("location")
            line = f"\u2022 {when}  {title}"
            if loc:
                line += f"  @ {loc}"
            lines.append(line)
        return "\\n".join(lines)

    def _fmt(self, ns, all_day):
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
        d = datetime.datetime.fromtimestamp(sec)
        if all_day:
            return d.strftime("%Y-%m-%d (종일)")
        return d.strftime("%H:%M")

    def get_today_schedule(self, __user__: dict = {}) -> str:
        """오늘의 일정을 OpenWebUI 캘린더에서 조회합니다. '오늘 일정', '오늘 스케줄' 질문에 사용."""
        deny = self._check_admin(__user__)
        if deny:
            return deny
        key = self._resolve_key()
        if not key:
            return "캘린더 도구 설정(밸브)에 OpenWebUI API 키를 먼저 입력해 주세요."
        today = datetime.date.today()
        start_iso = f"{today.isoformat()}T00:00:00"
        end_iso = f"{(today + datetime.timedelta(days=1)).isoformat()}T00:00:00"
        events, err = self._get_events(key, start_iso, end_iso)
        if err:
            return err
        return self._render(f"📅 {today.isoformat()} 오늘의 일정", events)

    def get_schedule_by_date(self, date: str, __user__: dict = {}) -> str:
        """특정 날짜의 일정을 조회합니다. '12월 25일 일정', '내일 일정', '2025-12-25 일정' 등에 사용.
        date 는 YYYY-MM-DD 형식으로 넘겨주세요 (상대표현은 실제 날짜로 변환해서 전달)."""
        deny = self._check_admin(__user__)
        if deny:
            return deny
        key = self._resolve_key()
        if not key:
            return "캘린더 도구 설정(밸브)에 OpenWebUI API 키를 먼저 입력해 주세요."
        try:
            d = datetime.date.fromisoformat((date or "").strip())
        except Exception:
            return "날짜 형식을 이해하지 못했습니다. YYYY-MM-DD 형식으로 알려주세요. 예: 2025-12-25"
        start_iso = f"{d.isoformat()}T00:00:00"
        end_iso = f"{(d + datetime.timedelta(days=1)).isoformat()}T00:00:00"
        events, err = self._get_events(key, start_iso, end_iso)
        if err:
            return err
        return self._render(f"📅 {d.isoformat()} 일정", events)

    def create_event(self, title: str, date: str, time: str = "", location: str = "", description: str = "", reminder_min: int = None, __user__: dict = {}) -> str:
        """캘린더에 새 일정을 등록합니다. '12월 25일 3시에 회의 등록해줘' 같은 요청에 사용.
        title: 일정 제목, date: YYYY-MM-DD, time: HH:MM(24시간, 없으면 종일), location: 장소(선택), description: 설명/메모(선택), reminder_min: 알림(분 전, 예 10=10분 전·60=1시간 전·1440=하루 전, 없으면 기본 10분)."""
        deny = self._check_admin(__user__)
        if deny:
            return deny
        key = self._resolve_key()
        if not key:
            return "캘린더 도구 설정(밸브)에 OpenWebUI API 키를 먼저 입력해 주세요."
        try:
            d = datetime.date.fromisoformat((date or "").strip())
        except Exception:
            return "날짜 형식을 이해하지 못했습니다. YYYY-MM-DD 형식으로 알려주세요. 예: 2025-12-25"
        t = (time or "").strip()
        all_day = not t
        if all_day:
            start_dt = datetime.datetime(d.year, d.month, d.day, 0, 0)
        else:
            try:
                hh, mm = t.split(":")
                start_dt = datetime.datetime(d.year, d.month, d.day, int(hh), int(mm))
            except Exception:
                return "시간 형식을 이해하지 못했습니다. HH:MM 형식으로 알려주세요. 예: 15:00"
        calendar_id = self._get_default_calendar_id(key)
        if not calendar_id:
            return "등록할 캘린더를 찾지 못했습니다. 오픈웹유아이에서 캘린더를 먼저 만들어 주세요."
        payload = {
            "calendar_id": calendar_id,
            "title": (title or "제목 없음").strip(),
            "start_at": int(start_dt.timestamp()) * 1_000_000_000,
            "all_day": bool(all_day),
        }
        if location:
            payload["location"] = location.strip()
        if description:
            payload["description"] = description.strip()
        # 알림(reminder): OpenWebUI 는 meta.alert_minutes 로 저장 (기본 10분 재정의)
        if reminder_min is not None:
            try:
                payload["meta"] = {"alert_minutes": int(reminder_min)}
            except (TypeError, ValueError):
                pass
        try:
            _s = requests.Session()
            _s.trust_env = False
            r = _s.post(
                f"{self._base_url()}/api/v1/calendars/events/create",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                json=payload, timeout=30, allow_redirects=False,
            )
        except Exception as e:
            return f"캘린더 서버 연결 실패: {e}"
        if r.status_code == 401:
            return "API 키 인증에 실패했습니다. 밸브의 키를 확인해 주세요."
        if r.status_code == 403:
            return "캘린더 접근 권한이 없습니다."
        if r.status_code >= 400:
            return f"일정 등록 실패 (HTTP {r.status_code})."
        when_txt = d.isoformat()
        if not all_day:
            when_txt += f" {start_dt.strftime('%H:%M')}"
        else:
            when_txt += " (종일)"
        extra = []
        if location:
            extra.append(f"장소: {location.strip()}")
        if reminder_min is not None:
            try:
                _rm = int(reminder_min)
                if _rm >= 1440 and _rm % 1440 == 0:
                    extra.append(f"알림: {_rm // 1440}일 전")
                elif _rm >= 60 and _rm % 60 == 0:
                    extra.append(f"알림: {_rm // 60}시간 전")
                else:
                    extra.append(f"알림: {_rm}분 전")
            except (TypeError, ValueError):
                pass
        if description:
            extra.append(f"설명: {description.strip()}")
        # 🔔 알림 시각에 관리자에게 전화+SMS: twilio-bot 예약 API 호출
        _reminder_note = ""
        if reminder_min is not None and getattr(self.valves, "ENABLE_CALL_SMS_REMINDER", True) \
           and getattr(self.valves, "TWILIO_BOT_SECRET", ""):
            try:
                _rm2 = int(reminder_min)
            except (TypeError, ValueError):
                _rm2 = 0
            if _rm2 > 0:
                try:
                    _bs = requests.Session()
                    _bs.trust_env = False
                    _rr = _bs.post(
                        f"{self.valves.TWILIO_BOT_URL}/calendar-reminder",
                        headers={"X-API-Secret": self.valves.TWILIO_BOT_SECRET,
                                 "Content-Type": "application/json"},
                        json={"title": payload["title"],
                              "start_epoch": int(start_dt.timestamp()),
                              "reminder_min": _rm2},
                        timeout=10,
                    )
                    if _rr.status_code == 200 and _rr.json().get("status") == "scheduled":
                        _reminder_note = " (알림 시각에 전화·문자 발송 예약됨)"
                except Exception:
                    pass  # 알림 예약 실패해도 일정 등록 자체는 성공 처리
        extra_txt = (" / " + ", ".join(extra)) if extra else ""
        return f"✅ 일정을 등록했습니다: {payload['title']} — {when_txt}{extra_txt}{_reminder_note}"

    def _find_event(self, key, date, title):
        """지정 날짜에서 제목이 일치(부분 포함)하는 이벤트를 찾아 (event, error) 반환."""
        try:
            d = datetime.date.fromisoformat((date or "").strip())
        except Exception:
            return None, "날짜 형식을 이해하지 못했습니다. YYYY-MM-DD 형식으로 알려주세요."
        start_iso = f"{d.isoformat()}T00:00:00"
        end_iso = f"{(d + datetime.timedelta(days=1)).isoformat()}T00:00:00"
        events, err = self._get_events(key, start_iso, end_iso)
        if err:
            return None, err
        if not events:
            return None, f"{d.isoformat()}에 등록된 일정이 없습니다."
        title = (title or "").strip()
        # 1) 정확 일치 우선
        exact = [e for e in events if (e.get("title") or "").strip() == title]
        if len(exact) == 1:
            return exact[0], None
        if len(exact) > 1:
            return None, f"'{title}' 일정이 {len(exact)}개 있습니다. 시간까지 알려주시면 정확히 찾을 수 있어요."
        # 2) 부분 포함
        partial = [e for e in events if title and title in (e.get("title") or "")]
        if len(partial) == 1:
            return partial[0], None
        if len(partial) > 1:
            names = ", ".join((e.get("title") or "?") for e in partial[:5])
            return None, f"비슷한 일정이 여러 개 있습니다: {names}. 제목을 정확히 알려주세요."
        return None, f"'{title}' 일정을 찾지 못했습니다. 그날 일정을 먼저 조회해 제목을 확인해 주세요."

    def delete_event(self, date: str, title: str, __user__: dict = {}) -> str:
        """캘린더에서 일정을 삭제합니다. '12월 25일 회의 삭제해줘' 같은 요청에 사용.
        date: YYYY-MM-DD, title: 삭제할 일정 제목."""
        deny = self._check_admin(__user__)
        if deny:
            return deny
        key = self._resolve_key()
        if not key:
            return "캘린더 도구 설정(밸브)에 OpenWebUI API 키를 먼저 입력해 주세요."
        ev, err = self._find_event(key, date, title)
        if err:
            return err
        ev_id = ev.get("id")
        if not ev_id:
            return "일정 식별자를 찾지 못해 삭제할 수 없습니다."
        try:
            _s = requests.Session()
            _s.trust_env = False
            r = _s.delete(
                f"{self._base_url()}/api/v1/calendars/events/{ev_id}",
                headers={"Authorization": f"Bearer {key}"},
                timeout=30, allow_redirects=False,
            )
        except Exception as e:
            return f"캘린더 서버 연결 실패: {e}"
        if r.status_code == 401:
            return "API 키 인증에 실패했습니다. 밸브의 키를 확인해 주세요."
        if r.status_code >= 400:
            return f"일정 삭제 실패 (HTTP {r.status_code})."
        _deleted_title = (ev.get('title') or title).strip()

        # 🔔 삭제된 일정에 걸린 알림도 함께 취소
        if getattr(self.valves, "ENABLE_CALL_SMS_REMINDER", True) \
           and getattr(self.valves, "TWILIO_BOT_SECRET", ""):
            try:
                _bs = requests.Session()
                _bs.trust_env = False
                _bs.post(
                    f"{self.valves.TWILIO_BOT_URL}/calendar-reminder",
                    headers={"X-API-Secret": self.valves.TWILIO_BOT_SECRET,
                             "Content-Type": "application/json"},
                    json={"cancel_only": True, "title": _deleted_title},
                    timeout=10,
                )
            except Exception:
                pass  # 알림 취소 실패해도 삭제 자체는 성공 처리

        return f"🗑️ '{_deleted_title}' 일정을 삭제했습니다."

    def update_event(self, date: str, title: str, new_date: str = "", new_time: str = "",
                     new_title: str = "", new_location: str = "", __user__: dict = {}) -> str:
        """캘린더 일정을 수정합니다. '12월 25일 회의를 3시로 바꿔줘' 같은 요청에 사용.
        date/title 로 대상을 찾고, new_date·new_time·new_title·new_location 중 준 값만 바꿉니다.
        시간만 바꾸려면 new_time, 날짜만 바꾸려면 new_date, 제목은 new_title 을 넣으세요."""
        deny = self._check_admin(__user__)
        if deny:
            return deny
        key = self._resolve_key()
        if not key:
            return "캘린더 도구 설정(밸브)에 OpenWebUI API 키를 먼저 입력해 주세요."
        ev, err = self._find_event(key, date, title)
        if err:
            return err
        ev_id = ev.get("id")
        if not ev_id:
            return "일정 식별자를 찾지 못해 수정할 수 없습니다."

        # 기존 값에서 시작
        cur_ns = 0
        try:
            cur_ns = int(ev.get("start_at") or 0)
        except (TypeError, ValueError):
            cur_ns = 0
        cur_dt = datetime.datetime.fromtimestamp(cur_ns // 1_000_000_000) if cur_ns else None

        # 대상 날짜/시간 계산
        if new_date.strip():
            try:
                nd = datetime.date.fromisoformat(new_date.strip())
            except Exception:
                return "새 날짜 형식을 이해하지 못했습니다. YYYY-MM-DD 로 알려주세요."
        else:
            nd = cur_dt.date() if cur_dt else datetime.date.today()

        all_day = bool(ev.get("all_day", False))
        if new_time.strip():
            try:
                hh, mm = new_time.strip().split(":")
                nt = datetime.time(int(hh), int(mm))
                all_day = False
            except Exception:
                return "새 시간 형식을 이해하지 못했습니다. HH:MM 로 알려주세요."
        else:
            nt = cur_dt.time() if (cur_dt and not all_day) else datetime.time(0, 0)

        new_start = datetime.datetime(nd.year, nd.month, nd.day, nt.hour, nt.minute)

        payload = {
            "title": (new_title.strip() or ev.get("title") or "제목 없음"),
            "start_at": int(new_start.timestamp()) * 1_000_000_000,
            "all_day": bool(all_day),
        }
        loc = new_location.strip() or ev.get("location") or ""
        if loc:
            payload["location"] = loc

        try:
            _s = requests.Session()
            _s.trust_env = False
            r = _s.post(
                f"{self._base_url()}/api/v1/calendars/events/{ev_id}/update",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                json=payload, timeout=30, allow_redirects=False,
            )
        except Exception as e:
            return f"캘린더 서버 연결 실패: {e}"
        if r.status_code == 401:
            return "API 키 인증에 실패했습니다. 밸브의 키를 확인해 주세요."
        if r.status_code >= 400:
            return f"일정 수정 실패 (HTTP {r.status_code})."
        when_txt = nd.isoformat() + ("" if all_day else f" {new_start.strftime('%H:%M')}")

        # 🔔 알림 재예약: 시간/날짜/제목이 바뀌었으면 옛 알림 취소 후 새 시각으로 다시 예약
        _reminder_note = ""
        _time_changed = (new_date.strip() or new_time.strip())
        _title_changed = bool(new_title.strip()) and new_title.strip() != (ev.get("title") or "").strip()
        if (_time_changed or _title_changed) \
           and getattr(self.valves, "ENABLE_CALL_SMS_REMINDER", True) \
           and getattr(self.valves, "TWILIO_BOT_SECRET", ""):
            # 기존 일정에 걸려 있던 알림(분 전) 값을 meta 에서 가져온다
            _old_rem = 0
            try:
                _meta = ev.get("meta") or {}
                _old_rem = int(_meta.get("alert_minutes") or 0)
            except (TypeError, ValueError):
                _old_rem = 0
            try:
                _bs = requests.Session()
                _bs.trust_env = False
                _body = {
                    "title": payload["title"],
                    "old_title": (ev.get("title") or "").strip(),
                    "start_epoch": int(new_start.timestamp()),
                    "reminder_min": _old_rem,
                }
                _rr = _bs.post(
                    f"{self.valves.TWILIO_BOT_URL}/calendar-reminder",
                    headers={"X-API-Secret": self.valves.TWILIO_BOT_SECRET,
                             "Content-Type": "application/json"},
                    json=_body, timeout=10,
                )
                if _rr.status_code == 200:
                    _st = _rr.json().get("status")
                    if _st == "scheduled":
                        _reminder_note = " (알림도 새 시각으로 다시 예약됨)"
                    elif _old_rem > 0:
                        _reminder_note = " (옛 알림 정리됨)"
            except Exception:
                pass  # 재예약 실패해도 수정 자체는 성공 처리

        return f"✏️ 일정을 수정했습니다: {payload['title']} — {when_txt}{_reminder_note}"
'''

print("9️⃣  캘린더 (조회+등록) Tool 등록 중...")
result9 = register_tool("calendar_today", "캘린더 (조회·등록·수정·삭제)", "OpenWebUI 캘린더에서 오늘/특정 날짜 일정 조회, 새 일정 등록, 기존 일정 수정·삭제. 밸브에 API 키 입력.", calendar_tool_code)
print(result9)

# ============================================================
# 🔟 실시간 귓속말 (AI 대리통화 라이브 지시) Tool  ★신규★
#    AI가 상대방과 통화 중일 때, 채팅/앱에서 "이렇게 말해"라고 지시하면
#    AI가 다음 발화에 자연스럽게 반영해서 말한다.
# ============================================================
live_whisper_tool_code = '''\\
"""
title: 실시간 귓속말 (대리통화 지시)
author: Live Whisper Tool
description: AI가 상대방과 통화하는 도중, 관리자가 실시간으로 "이렇게 말해"라고 지시하면 AI가 다음 발화에 자연스럽게 반영합니다.
version: 1.0.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def list_active_calls(self) -> str:
        """지금 진행 중인 통화 목록을 확인합니다.

        상대방 이름/번호, 방향(수신/대리전화), 최근 대화, 대기 중인 지시 수를 보여줍니다.
        관리자가 "지금 통화 중이야?", "누구랑 통화 중이야?" 라고 물으면 이 함수를 사용하세요.
        """
        try:
            r = requests.get(f"{TOOL_SERVER}/tools/whisper/active-calls", timeout=10)
            if r.status_code != 200:
                return f"통화 목록 조회 실패: {r.text}"
            calls = r.json().get("calls", [])
            if not calls:
                return "지금 진행 중인 통화가 없습니다."
            lines = []
            for i, c in enumerate(calls, 1):
                d = "수신전화" if c.get("direction") == "inbound" else "대리전화(안부)"
                lines.append(
                    f"{i}. {c.get('name','상대방')} ({d}) {c.get('number','')}\\n"
                    f"   최근 상대방 말: {c.get('last_speech','') or '-'}\\n"
                    f"   최근 AI 말: {c.get('last_ai','') or '-'}\\n"
                    f"   대기 중인 지시: {c.get('pending_whispers',0)}건"
                )
            return "진행 중 통화:\\n" + "\\n".join(lines)
        except Exception as e:
            return f"오류: {e}"

    def whisper(self, instruction: str, target: str = "") -> str:
        """진행 중인 통화의 AI에게 실시간으로 "이렇게 말해"라고 지시합니다.

        AI는 이 지시를 다음 발화에 자연스럽게 녹여서 상대방에게 말합니다.
        (AI라거나 지시받았다는 티는 내지 않습니다.)

        instruction: AI가 상대방에게 전할 내용 (예: "곧 찾아뵙겠다고 전해줘", "목소리를 더 밝게")
        target: (선택) 통화가 여러 개일 때 대상 이름/번호. 통화가 1개면 비워두세요.

        사용 예시:
            "곧 방문한다고 전해줘" → instruction="곧 방문하겠다고 전해주세요"
            "김철수한테 다음 주에 연락한다고 해" → target="김철수", instruction="다음 주에 다시 연락드리겠다고 전해주세요"
        """
        try:
            if not (instruction or "").strip():
                return "전할 내용(instruction)이 비어 있습니다."
            r = requests.post(
                f"{TOOL_SERVER}/tools/whisper/send",
                json={"instruction": instruction, "target": target},
                timeout=10
            )
            if r.status_code != 200:
                return f"지시 전달 실패: {r.text}"
            data = r.json()
            status = data.get("status")
            if status == "queued":
                return f"✅ {data.get('target','상대방')}님과의 통화에 지시를 전달했습니다. 곧 AI가 자연스럽게 반영해서 말합니다."
            if status == "no_active_call":
                return "지금 진행 중인 통화가 없어 지시를 전달할 수 없습니다."
            if status == "ambiguous":
                names = ", ".join(c.get("name","") for c in data.get("candidates", []))
                return f"진행 중 통화가 여러 개입니다: {names}. target에 이름을 지정해 주세요."
            return data.get("message", "처리되었습니다.")
        except Exception as e:
            return f"오류: {e}"

    def cancel_whisper(self, target: str = "") -> str:
        """아직 반영되지 않은(대기 중인) 실시간 지시를 취소합니다.

        target: (선택) 대상 이름/번호. 통화가 1개면 비워두세요.
        """
        try:
            r = requests.post(
                f"{TOOL_SERVER}/tools/whisper/clear",
                json={"target": target},
                timeout=10
            )
            if r.status_code != 200:
                return f"취소 실패: {r.text}"
            data = r.json()
            if data.get("status") == "cleared":
                return f"대기 중이던 지시 {data.get('removed',0)}건을 취소했습니다."
            if data.get("status") == "no_active_call":
                return "진행 중인 통화가 없습니다."
            if data.get("status") == "ambiguous":
                return "통화가 여러 개입니다. target에 이름을 지정해 주세요."
            return data.get("message", "처리되었습니다.")
        except Exception as e:
            return f"오류: {e}"
'''

print("🔟  실시간 귓속말 (대리통화 지시) Tool 등록 중...")
result10 = register_tool("live_whisper", "실시간 귓속말 (대리통화 지시)", "AI가 상대방과 통화 중일 때 관리자가 '이렇게 말해'라고 실시간 지시하면 AI가 다음 발화에 자연스럽게 반영. 진행 중 통화 조회/지시 전달/지시 취소.", live_whisper_tool_code)
print(result10)

# ============================================================
# 1️⃣1️⃣ 음성엔진 설정 (STT/TTS 밸브 교체) Tool  ★신규★
#    진짜 실시간 통화에서 쓰는 STT/TTS 제공자·키·음성을
#    채팅/앱에서 바꾼다 → twilio-bot 이 voice_config.json 에 저장.
# ============================================================
voice_engine_tool_code = '''\\
"""
title: 음성엔진 설정 (실시간 STT/TTS)
author: webmaster@vulva.sex
description: 진짜 실시간 통화의 STT(음성인식)/TTS(음성합성) 제공자·API키·음성을 밸브(⚙️ 설정)에 입력하고, 도구를 실행하면 저장됩니다. 다음 통화부터 적용.
version: 2.0.0
"""
import requests
from pydantic import BaseModel, Field


class Tools:
    class Valves(BaseModel):
        STT_PROVIDER: str = Field(
            default="deepgram",
            description="음성인식(STT) 제공자. 현재 지원: deepgram",
        )
        DEEPGRAM_API_KEY: str = Field(
            default="",
            description="Deepgram API 키 (음성인식용). console.deepgram.com 에서 발급.",
        )
        STT_MODEL: str = Field(
            default="nova-2",
            description="음성인식 모델 (예: nova-2, nova-3).",
        )
        TTS_PROVIDER: str = Field(
            default="elevenlabs",
            description="음성합성(TTS) 제공자. 지원: elevenlabs 또는 deepgram",
        )
        ELEVENLABS_API_KEY: str = Field(
            default="",
            description="ElevenLabs API 키 (음성합성용). elevenlabs.io 에서 발급. TTS 제공자가 deepgram 이면 Deepgram 키를 여기 넣으세요.",
        )
        TTS_VOICE: str = Field(
            default="21m00Tcm4TlvDq8ikWAM",
            description="음성 ID. ElevenLabs 음성 ID(기본 Rachel) 또는 Deepgram Aura 모델명.",
        )
        TTS_MODEL: str = Field(
            default="eleven_flash_v2_5",
            description="음성합성 모델 (ElevenLabs: eleven_flash_v2_5 / Deepgram: aura-asteria-en 등).",
        )
        LANGUAGE: str = Field(
            default="ko",
            description="통화 언어 코드 (ko, en, ja, zh).",
        )
        TOOL_SERVER: str = Field(
            default="http://openapi-tools:8000",
            description="도구 서버 내부 주소 (보통 변경 불필요).",
        )

    def __init__(self):
        self.valves = self.Valves()
        # 밸브 저장 시 OpenWebUI가 __init__ 을 다시 호출한다 →
        # 이 시점에 자동으로 서버에 반영해서 "저장 즉시 적용"이 되게 한다.
        try:
            self._sync_to_server()
        except Exception:
            pass

    def _build_payload(self):
        v = self.valves
        payload = {
            "stt_provider": (v.STT_PROVIDER or "").strip(),
            "stt_api_key":  (v.DEEPGRAM_API_KEY or "").strip(),
            "stt_model":    (v.STT_MODEL or "").strip(),
            "tts_provider": (v.TTS_PROVIDER or "").strip(),
            "tts_api_key":  (v.ELEVENLABS_API_KEY or "").strip(),
            "tts_voice":    (v.TTS_VOICE or "").strip(),
            "tts_model":    (v.TTS_MODEL or "").strip(),
            "language":     (v.LANGUAGE or "").strip(),
        }
        return {k: val for k, val in payload.items() if val != ""}

    def _sync_to_server(self):
        """밸브 값을 서버(voice_config.json)에 저장. 저장된 항목 목록 반환(없으면 [])."""
        payload = self._build_payload()
        if not payload:
            return []
        server = (self.valves.TOOL_SERVER or "http://openapi-tools:8000").rstrip("/")
        r = requests.post(f"{server}/tools/voice-config", json=payload, timeout=10)
        if r.status_code != 200:
            raise RuntimeError(r.text)
        return r.json().get("applied_fields", [])

    def apply_voice_settings(self) -> str:
        """⚙️ 밸브(설정)에 입력한 STT/TTS 제공자·API키·음성을 지금 즉시 저장/재적용합니다.
        보통은 밸브 저장 시 자동 반영되지만, 수동으로 다시 적용하고 싶을 때 사용합니다."""
        try:
            fields = self._sync_to_server()
            if not fields:
                return "밸브(⚙️ 설정)에 값이 비어 있습니다. 먼저 STT/TTS 제공자·키·음성을 입력해 주세요."
            return f"✅ 음성엔진 설정을 저장했습니다. 적용 항목: {', '.join(fields)}\\n다음 통화부터 반영됩니다."
        except Exception as e:
            return f"오류: {e}"

    def get_voice_engine(self) -> str:
        """현재 저장된 실시간 음성엔진(STT/TTS) 상태를 확인합니다. (API 키는 가려서 표시)"""
        # 조회 전에 밸브 최신값을 한 번 더 동기화 (즉시 반영 보강)
        try:
            self._sync_to_server()
        except Exception:
            pass
        server = (self.valves.TOOL_SERVER or "http://openapi-tools:8000").rstrip("/")
        try:
            r = requests.get(f"{server}/tools/voice-config", timeout=10)
            if r.status_code != 200:
                return f"조회 실패: {r.text}"
            cfg = r.json().get("config", {})
            if not cfg:
                return "아직 저장된 설정이 없습니다. 밸브(⚙️)에 값을 넣으면 자동 저장되며, 기본값(Deepgram + ElevenLabs)이 사용됩니다."
            return (
                "현재 실시간 음성엔진 설정:\\n"
                f"- STT 제공자: {cfg.get('stt_provider','deepgram')} (모델: {cfg.get('stt_model','nova-2')})\\n"
                f"- STT 키: {cfg.get('stt_api_key','(미설정)')}\\n"
                f"- TTS 제공자: {cfg.get('tts_provider','elevenlabs')} (모델: {cfg.get('tts_model','')})\\n"
                f"- TTS 키: {cfg.get('tts_api_key','(미설정)')}\\n"
                f"- 음성: {cfg.get('tts_voice','')}\\n"
                f"- 언어: {cfg.get('language','ko')}"
            )
        except Exception as e:
            return f"오류: {e}"
'''

print("1️⃣1️⃣  음성엔진 설정 (STT/TTS 밸브) Tool 등록 중...")
result11 = register_tool("voice_engine_config", "음성엔진 설정 (실시간 STT/TTS)", "밸브(⚙️)에 STT/TTS 제공자·API키·음성을 입력하고 적용하면 실시간 통화에 반영. 다음 통화부터 적용.", voice_engine_tool_code)
print(result11)

# ============================================================
# 1️⃣2️⃣ 기억의 앵커 (과거 통화 회상) Tool  ★신규★
#    전화번호/이름으로 과거 통화 기억을 검색하거나 수동 저장.
#    (통화 중 자동 회상·주제유도는 twilio-bot/realtime-voice 가 자동 처리)
# ============================================================
memory_anchor_tool_code = '''\\
"""
title: 기억의 앵커 (과거 통화 회상)
author: webmaster@vulva.sex
description: 특정 사람과의 과거 통화 기억(주제·감정·요약)을 전화번호나 이름으로 검색합니다. 통화 중에는 AI가 비슷한 조건의 기억을 자동으로 떠올려 대화를 이어갑니다.
version: 1.0.0
"""
import requests

TOOL_SERVER = "http://openapi-tools:8000"

class Tools:
    def recall_memory(self, name: str = "", phone_number: str = "", query: str = "") -> str:
        """특정 사람과의 과거 통화 기억을 검색합니다.

        name: 상대방 이름 (예: 김철수)
        phone_number: 전화번호 (예: +821011112222). 이름만으로도 검색 가능.
        query: (선택) 찾고 싶은 주제/키워드 (예: "이직", "건강")

        사용 예시:
            "김철수랑 예전에 무슨 얘기했지?" → name="김철수"
            "지난번 통화에서 이직 얘기 찾아줘" → query="이직"
        """
        try:
            payload = {"name": name, "phone_number": phone_number, "query": query}
            r = requests.post(f"{TOOL_SERVER}/tools/memory/recall", json=payload, timeout=10)
            if r.status_code != 200:
                return f"기억 검색 실패: {r.text}"
            mems = r.json().get("memories", [])
            if not mems:
                return f"{name or phone_number}님과의 저장된 통화 기억이 없습니다."
            lines = [f"🧠 {name or phone_number}님과의 과거 통화 기억:"]
            for i, m in enumerate(mems, 1):
                when = f"{m.get('date','')} {m.get('time_slot','')}".strip()
                piece = m.get("summary") or m.get("topic") or "(내용 없음)"
                extra = []
                if m.get("emotion"): extra.append(f"감정:{m['emotion']}")
                if m.get("weather"): extra.append(f"날씨:{m['weather']}")
                tail = f" ({', '.join(extra)})" if extra else ""
                lines.append(f"{i}. [{when}] {piece}{tail}")
            return "\\n".join(lines)
        except Exception as e:
            return f"오류: {e}"

    def save_memory(self, name: str, text: str, phone_number: str = "", summary: str = "") -> str:
        """통화 기억을 수동으로 저장합니다. (보통은 통화 종료 시 자동 저장됨)

        name: 상대방 이름
        text: 대화 내용 또는 기억할 내용
        phone_number: (선택) 전화번호
        summary: (선택) 한 문장 요약
        """
        try:
            if not (text or "").strip():
                return "저장할 내용(text)이 비어 있습니다."
            payload = {"name": name, "phone_number": phone_number, "text": text, "summary": summary}
            r = requests.post(f"{TOOL_SERVER}/tools/memory/save", json=payload, timeout=10)
            if r.status_code != 200:
                return f"저장 실패: {r.text}"
            status = r.json().get("status")
            if status == "saved":
                return f"✅ {name}님과의 통화 기억을 저장했습니다."
            return f"저장 건너뜀 (내용이 너무 짧음)."
        except Exception as e:
            return f"오류: {e}"
'''

print("1️⃣2️⃣  기억의 앵커 (과거 통화 회상) Tool 등록 중...")
result12 = register_tool("memory_anchor", "기억의 앵커 (과거 통화 회상)", "전화번호/이름으로 과거 통화 기억(주제·감정·요약)을 검색하거나 수동 저장. 통화 중 AI가 비슷한 조건의 기억을 자동 회상해 대화 유도.", memory_anchor_tool_code)
print(result12)

# ============================================================
# 🔟 채팅용 커스텀 모델 등록 (temperature 낮춤 + 도구 강제 프롬프트)
#    - 이름을 번호 칸에 넣거나 이름/메시지를 왜곡하는 문제를 줄이기 위해
#      temperature=0.1 로 고정하고, 번호 조회를 강제하는 시스템 프롬프트를 넣는다.
# ============================================================
CHAT_BASE_MODEL = os.getenv("CHAT_BASE_MODEL", "").strip()
CHAT_MODEL_ID   = "phone-assistant-chat"
CHAT_MODEL_NAME = "통신 비서 (Llama 3.3 70B)"

CHAT_SYSTEM_PROMPT = """당신은 전화·문자·연락처·일정을 관리하는 한국어 비서입니다.

# 연락처 및 통신 도구 사용 규칙

## 핵심 원칙
전화번호가 필요한 모든 작업(문자 발송, 전화 걸기)을 수행하기 전에,
반드시 연락처 조회 도구로 수신자의 전화번호를 먼저 확인하라.
전화번호를 임의로 생성하거나 추측하지 말 것.
사용자가 말한 이름과 메시지를 절대로 바꾸지 말고 그대로 사용하라.

## 문자(SMS) 발송 시
1. 사용자가 "OOO에게 문자 보내줘"라고 하면, phone_number 자리에 이름 OOO을 그대로 넣어라.
   (서버가 이름을 실제 번호로 조회한다. 번호를 지어내지 마라.)
2. 메시지 내용은 사용자가 말한 문장을 글자 그대로 옮겨라. 요약·변형 금지.
3. 발송 후 성공/실패 여부를 사용자에게 명확히 알린다.

## 전화(Call) 걸기 시
1. 사용자가 "OOO에게 전화 걸어줘"라고 하면, name 자리에 이름 OOO을 그대로 넣어라.
2. 전달할 말이 있으면 message에 사용자의 문장을 그대로 넣어라.
3. 발신 후 연결 상태를 사용자에게 알린다.

## 절대 금지 사항
- 연락처 조회 없이 번호를 지어내는 것
- 이름을 다른 이름으로 바꾸는 것 (예: 박익제 → 박학총)
- 메시지 내용을 임의로 바꾸거나 요약하는 것
- 실패를 성공처럼 보고하는 것"""

def register_chat_model():
    if not CHAT_BASE_MODEL:
        # 🔒 base 모델이 없으면(예: Groq 미설정, Ollama 채팅모델 없음) 커스텀 모델을
        #    만들지 않는다. base 없는 커스텀 모델은 선택란에서 깨져 보이거나 호출이 실패한다.
        return "SKIP: base 모델이 없어 커스텀 모델 등록 생략 (Ollama/Groq 모델을 먼저 준비하세요)"
    payload = {
        "id": CHAT_MODEL_ID,
        "name": CHAT_MODEL_NAME,
        "base_model_id": CHAT_BASE_MODEL,
        "meta": {
            "profile_image_url": "/static/favicon.png",
            "description": "번호 조회 강제 + temperature 0.1로 이름/메시지 왜곡을 줄인 통신 비서",
            "capabilities": {"vision": False, "citations": True},
        },
        "params": {
            "system": CHAT_SYSTEM_PROMPT,
            "temperature": 0.1,
            "top_p": 0.9,
        },
    }
    data = json.dumps(payload).encode()
    headers = {"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"}
    for attempt in range(3):
        req = urllib.request.Request(
            "http://localhost:3000/api/v1/models/create",
            data=data, headers=headers, method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                d = json.loads(resp.read())
                return f"SUCCESS: {d.get('name', CHAT_MODEL_NAME)}"
        except urllib.error.HTTPError as e:
            msg = e.read().decode()[:300]
            low = msg.lower()
            if any(kw in low for kw in ["already", "exists", "duplicate", "unique", "conflict"]):
                # 이미 있으면 UPDATE
                try:
                    up = urllib.request.Request(
                        f"http://localhost:3000/api/v1/models/id/{CHAT_MODEL_ID}/update",
                        data=data, headers=headers, method="POST"
                    )
                    with urllib.request.urlopen(up, timeout=30) as r2:
                        d2 = json.loads(r2.read())
                        return f"UPDATED: {d2.get('name', CHAT_MODEL_NAME)}"
                except Exception as e2:
                    return f"FAIL(update): {CHAT_MODEL_NAME} - {e2}"
            if attempt < 2:
                time.sleep(3)
            else:
                return f"FAIL: {CHAT_MODEL_NAME} - {msg}"
        except Exception as e:
            if attempt < 2:
                time.sleep(3)
            else:
                return f"ERROR: {CHAT_MODEL_NAME} - {e}"
    return f"FAIL: {CHAT_MODEL_NAME} - 3회 재시도 실패"

print("➕ 채팅용 커스텀 모델 등록 중 (temperature 0.1)...")
result_chat = register_chat_model()
print(result_chat)
PYEOF

  # 🆕 커스텀 채팅 모델의 base 결정: Groq 우선, 없으면 Ollama 채팅 모델, 둘 다 없으면 빈값(등록 생략)
  if [ "$USE_GROQ" = true ] && [ -n "$GROQ_API_KEY" ]; then
    CHAT_BASE_MODEL="llama-3.3-70b-versatile"
  elif [ "$USE_OLLAMA" = true ] && [ -n "${OLLAMA_CHAT_MODEL:-}" ]; then
    CHAT_BASE_MODEL="$OLLAMA_CHAT_MODEL"
  else
    CHAT_BASE_MODEL=""
  fi
  TOOL_RESULT=$(CHAT_BASE_MODEL="$CHAT_BASE_MODEL" python3 /tmp/register_tools.py "$OW_JWT" 2>&1)
  
  if echo "$TOOL_RESULT" | grep -q "SUCCESS\|SKIP\|UPDATED\|RECREATED"; then
    echo "   ✅ OpenWebUI Tool 자동 등록 완료!"
    echo ""
    echo "$TOOL_RESULT" | while IFS= read -r line; do
      echo "      $line"
    done
  fi

  # 🆕 모델 목록 캐시 갱신 — 방금 pull/등록한 모델이 선택란에 바로 보이도록
  #    OpenWebUI를 재시작한다. (OpenWebUI는 모델 목록을 캐시하므로 재시작 없이는
  #    드롭다운이 비어 보일 수 있음.)
  echo "   🔄 모델 목록 반영을 위해 OpenWebUI 재시작 중..."
  docker compose restart open-webui >/dev/null 2>&1 || true
  sleep 5
  echo "   ✅ 모델 목록 갱신 완료 (브라우저에서 새로고침하면 모델이 보입니다)"
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
echo "   ${WEBUI_CUSTOM_NAME}        : http://localhost:3000"
echo "   OpenAPI Tool Docs : http://localhost:8000/docs"
echo "   Qdrant Dashboard  : http://localhost:6333/dashboard"
echo ""
echo "🔐 관리자 계정:"
echo "   이메일: ${OW_EMAIL}"
echo "   비밀번호: ${OW_PASSWORD}"
echo ""
echo "✅ 자동 등록된 Tool (11개):"
echo "   1️⃣  전화 어시스턴트 - 전화 걸기, 연락처 관리, 통화기록 조회"
echo "   2️⃣  RAG 문서 검색 - PDF 문서에서 정보 검색"
echo "   3️⃣  SMS 보내기 - 지정한 번호로 문자 전송 (답장 자동 전달)"
echo "   4️⃣  예약 스케줄러 - 전화/SMS 예약 등록·조회·삭제"
echo "   5️⃣  통화 녹음 관리 - 녹음 ON/OFF, MP3 목록"
echo "   6️⃣  PDF 보고서 관리 - 통화 보고서 ON/OFF, 목록"
echo "   7️⃣  기능 상태 확인 - 녹음/PDF 상태 + 파일 수"
echo "   8️⃣  미디어 관리 - 사진/동영상/음성/PDF 업로드·링크"
echo "   9️⃣  캘린더 - 오늘/특정일 일정 조회·등록·수정·삭제"
echo "   🔟  실시간 귓속말 (대리통화 지시) 🆕 - 통화 중 'AI에게 이렇게 말해' 실시간 지시"
echo "   1️⃣1️⃣  음성엔진 설정 (실시간 STT/TTS) 🆕 - 밸브에서 Deepgram/ElevenLabs 등 교체"
echo ""
echo "📱 사용 예시:"
echo "   전화: '김철수한테 안부전화 해줘. 어떻게 지내세요?'"
echo "   SMS: '김철수한테 문자 보내줘: 내일 회의 있어요'"
echo "   → 김철수님 답장 → 자동으로 관리자에게 전달 ✅"
echo "   RAG: 'PDF 문서에서 환불 정책 찾아줘'"
echo ""
echo "🤫 실시간 귓속말 (AI 대리통화 라이브 지시) 🆕:"
echo "   [상황] AI가 상대방과 통화하는 도중, 관리자가 실시간으로 지시"
echo "   ▸ 텔레그램: 봇에게 아래처럼 전송 (즉시 반영)"
echo "       '이렇게 말해: 곧 찾아뵙겠다고 전해줘'"
echo "       '귓속말: 목소리 톤을 더 밝게'"
echo "       '김철수 이렇게 말해: 다음 주에 다시 연락한다고 해'  (통화 여러 개일 때)"
echo "       '/calls' 또는 '통화목록'  → 진행 중 통화 확인"
echo "   ▸ OpenWebUI 채팅/앱: '실시간 귓속말' 도구 사용"
echo "       '지금 통화 중이야?'          → 진행 중 통화 목록"
echo "       '곧 방문한다고 전해줘'        → AI가 다음 발화에 자연스럽게 반영"
echo "   [원리] 상대방이 말을 마치는 순간(약 1~3초 뒤) AI 발화에 지시가 녹아 나감"
echo "   [설정] 텔레그램 실시간 지시는 .env 의 TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID 필요"
echo "          (미설정이어도 OpenWebUI 채팅/앱 도구로는 바로 사용 가능)"
echo ""
echo "🎙️ 진짜 실시간 대화 (Media Streams) 🆕:"
if [ "${REALTIME_MODE_INPUT:-false}" = "true" ]; then
  echo "   상태: ✅ 켜짐 (말하는 도중에도 AI가 즉시 끼어들어 반응)"
else
  echo "   상태: ⭐️ 꺼짐 (한 문장씩 주고받기). 켜려면 아래 참고"
fi
echo "   ▸ 켜는 법: ~/OpenWebUI/.env 에서 REALTIME_MODE=true 로 변경 후"
echo "             cd ~/OpenWebUI && docker compose up -d"
echo "   ▸ 필수 조건: SERVER_DOMAIN 이 https:// 공개 도메인이어야 함 (Twilio가 wss 접속)"
echo "             localhost 면 실시간 불가 → 자동으로 기존 방식으로 폴백"
echo "   ▸ STT/TTS 변경: OpenWebUI 채팅/앱에서 '음성엔진 설정' 도구 사용"
echo "       '지금 음성엔진 설정 보여줘'              → 현재 STT/TTS 확인"
echo "       'TTS 음성을 abc123 으로 바꿔줘'          → ElevenLabs 음성 교체"
echo "       'STT를 deepgram nova-3 로 바꿔줘'        → 음성인식 모델 교체"
echo "       'ElevenLabs 키를 sk-... 로 설정해줘'     → 키 교체 (다음 통화부터 적용)"
echo "   ▸ 기본 엔진: Deepgram(STT) + ElevenLabs Flash v2.5(TTS)"
echo "   ▸ 동작: 상대방이 말을 시작하면 AI가 하던 말을 즉시 멈추고 반응 (barge-in)"
echo "   ▸ 실시간 귓속말도 그대로 작동 — 텔레그램/앱 지시가 다음 발화에 즉시 반영"
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

echo "🔐 보안 강화 (21항목):"
echo "   기존 13항목 + 신규 8항목:"
echo "   🆕 Docker Secrets: 민감정보 /run/secrets/ 분리 저장"
echo "   🆕 JSON 감사 로그: /var/log/nginx/audit.json.log"
echo "   🆕 Cloudflare Tunnel: HTTPS 외부 접속 (설정 시)"
echo "   🆕 민감 입력 마스킹: API Key/Token/비밀번호/PIN → Enter 후 **** 처리"
echo "   🆕 기본 비밀번호 제거: 빈 입력 시 랜덤 자동 생성"
echo "   🆕 PIN 잠금 영구 저장: 파일 기반 + 30분 자동 해제"
echo "   🆕 TTS 인젝션 방지: voice-report 내부 저장소 방식"
echo "   🆕 .gitignore 자동 생성: secrets/.env 유출 방지"
echo ""
echo "🌐 다국어 지원 "
echo "   자동 감지: 전화번호 국가코드 기반"
echo "   +82 → 한국어 | +1/+44 → English | +81 → 日本語 | +86 → 中文"
echo "   설정 변경: ~/OpenWebUI/twilio-bot/ai_config.py"
echo "   기본 언어: DEFAULT_LANG (현재: ko)"
echo "   적용 방법: cd ~/OpenWebUI && docker compose restart twilio-bot"
echo ""
echo "📋 감사 로그 조회:"
echo "   최근 20건:     cd ~/OpenWebUI && ./view-audit-log.sh"
echo "   실시간 모니터: cd ~/OpenWebUI && ./view-audit-log.sh tail"
echo "   에러만:        cd ~/OpenWebUI && ./view-audit-log.sh errors"
echo ""


############################################
# 13. 📅 전화 캘린더 연동 (밸브 키 공유 방식)
#     제작자: <webmaster@vulva.sex>
#
#  채팅 캘린더 도구의 밸브에 입력한 OpenWebUI API 키를,
#  전화 봇도 같은 키로 공유해서 "오늘 일정"을 음성 안내한다.
#
#  동작:
#   - 채팅 도구가 호출되면 밸브 키를 open-webui-data 볼륨의
#     shared-key/ 폴더에 저장한다.
#   - 전화 봇 컨테이너도 그 볼륨을 마운트(:ro)해서 /shared-key 로 읽는다.
#   - 전화로 "오늘 일정 알려줘" → 봇이 그 키로 캘린더 조회 → 음성 안내.
#
#  ▸ 기존 docker-compose.yml / override 는 건드리지 않고
#    별도 compose 파일(docker-compose.calendar.yml)로 -f 병합.
#  ▸ 별도 키 입력 불필요: 채팅 밸브에 1번 넣으면 전화도 같이 작동.
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "📅 전화 캘린더 연동 (밸브 키 공유) 설정 중..."
echo "└────────────────────────────────────────────┘"

# ════════════════════════════════════════════════════════════
# [재발 방지 #1] 캘린더 볼륨 마운트는 이미 메인 docker-compose.yml 의
#   twilio-bot 에 직접 포함되어 있습니다 (open-webui-data:/owui-data:ro).
#   → 'docker compose up' / 'restart' / 서버 재부팅 자동기동 등
#     어떤 방식으로 띄워도 캘린더 마운트가 항상 붙습니다.
# ════════════════════════════════════════════════════════════
echo "   ✅ 캘린더 볼륨 마운트가 메인 compose에 포함됨 (항상 자동 연결)"

# [재발 방지 #2] .env 에 COMPOSE_FILE 을 설정해 이중 안전장치 적용.
#   혹시 override 등 다른 파일이 있어도 항상 함께 읽히도록 보장.
_ENV_FILE="$BASE_DIR/.env"
_COMPOSE_LIST="docker-compose.yml"
[ -f "$BASE_DIR/docker-compose.override.yml" ] && _COMPOSE_LIST="${_COMPOSE_LIST}:docker-compose.override.yml"
if [ -f "$_ENV_FILE" ]; then
  if grep -q "^COMPOSE_FILE=" "$_ENV_FILE"; then
    # 기존 값 교체
    sed -i "s|^COMPOSE_FILE=.*|COMPOSE_FILE=${_COMPOSE_LIST}|" "$_ENV_FILE"
  else
    printf '\n# 재발 방지: compose 파일을 항상 함께 읽도록 고정\nCOMPOSE_FILE=%s\n' "$_COMPOSE_LIST" >> "$_ENV_FILE"
  fi
else
  printf '# 재발 방지: compose 파일을 항상 함께 읽도록 고정\nCOMPOSE_FILE=%s\n' "$_COMPOSE_LIST" > "$_ENV_FILE"
fi
echo "   ✅ .env 에 COMPOSE_FILE 고정 (이중 안전장치)"

# [호환성] 별도 compose 파일도 백업으로 생성 (수동 -f 병합용, 선택)
#   메인에 이미 마운트가 있으므로 필수는 아니지만, 과거 방식 호환을 위해 유지.
cat > "$BASE_DIR/docker-compose.calendar.yml" <<'CALCOMPOSEEOF'
# 제작자: <webmaster@vulva.sex>
# [참고] 캘린더 마운트는 이미 메인 docker-compose.yml 에 포함되어 있습니다.
# 이 파일은 과거 방식 호환/수동 병합용 백업입니다. 보통 필요 없습니다.
services:
  twilio-bot:
    environment:
      - OPENWEBUI_URL=http://open-webui:8080
    volumes:
      - open-webui-data:/owui-data:ro

volumes:
  open-webui-data:
    external: true
    name: openwebui_open-webui-data
CALCOMPOSEEOF

# calendar-up.sh: 이제 메인 compose 만으로 충분 (재발 방지 적용됨)
cat > "$BASE_DIR/calendar-up.sh" <<'CALUPEOF'
#!/usr/bin/env bash
# 전화 봇 재기동 (캘린더 마운트는 메인 compose에 포함되어 항상 적용됨)
set -e
cd "$(dirname "$0")"
# COMPOSE_FILE 이 .env 에 고정되어 있으므로 단순 up 으로도 캘린더가 붙습니다.
docker compose up -d twilio-bot
CALUPEOF
chmod +x "$BASE_DIR/calendar-up.sh"
echo "   ✅ calendar-up.sh 생성 (메인 compose 기반)"

# 봇 기동 (메인 compose — 마운트 이미 포함)
cd "$BASE_DIR"
if docker compose up -d twilio-bot 2>/dev/null; then
  echo "   ✅ 전화 봇 기동 완료 (캘린더 볼륨 자동 연결)"
else
  echo "   ⚠️  봇 기동 확인 필요: cd $BASE_DIR && docker compose up -d twilio-bot"
fi

echo ""
echo "┌────────────────────────────────────────────┐"
echo "📅 전화 + 채팅 캘린더 — 사용 안내"
echo "└────────────────────────────────────────────┘"
echo "   1) OpenWebUI 관리자 로그인 → 설정 → 계정 → API 키 발급 (sk-...)"
echo "   2) 워크스페이스 > 도구 > \"캘린더 (오늘 일정)\" > ⚙️ 밸브에 키 입력 > 저장"
echo "   3) 채팅에서 그 도구를 한 번 사용 (\"오늘 일정 알려줘\")"
echo "      → 이때 키가 공유 폴더에 저장되어 전화 봇도 쓸 수 있게 됨"
echo "   4) 이제 전화로도 \"오늘 일정 알려줘\" → 음성 안내"
echo ""
echo "   ※ 키는 채팅 밸브에 1번만 넣으면 전화·채팅 모두 작동합니다."
echo "   ✅ [재발 방지] 캘린더 마운트가 메인 compose에 포함 + .env COMPOSE_FILE 고정"
echo "      → 'docker compose up', 'restart', 서버 재부팅 모두 캘린더 자동 유지"
echo "   ⚠️  OpenWebUI 0.9.0 이상이어야 내장 캘린더가 있습니다."
echo ""
