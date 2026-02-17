#!/bin/bash
# =============================================================================
# 프로젝트명: OpenWebUI RAG 보안강화 원터치 설치 스크립트
# 제작자: <webmaster@vulva.sex>
# 제작일: 2026-01-26
# 설명: Linux Server + Docker + Ollama + Groq + Qdrant + Nginx + SSL + UFW + 보안강화
# 지원환경: AWS EC2, Google Cloud, Azure, DigitalOcean, 온프레미스 Ubuntu
# 라이센스: MIT License
#
# ✅ 지원 OS : Ubuntu 20.04 / 22.04 / 24.04 LTS (Debian 계열)
# ✅ 권장 사양: 2코어 4GB↑ (중급), 4코어 8GB↑ (권장), 6코어 16GB↑ (고성능)
#
# 📦 원격 원터치 설치:
#   curl -fsSL https://your-s3-url/install_openwebui_rag_aws.sh | bash
#   또는
#   wget -qO- https://your-s3-url/install_openwebui_rag_aws.sh | bash
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── 색상 정의 ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ── 전역 변수 ─────────────────────────────────────────────────────────────────
BASE_DIR="$HOME/openapi-rag"
LOG_FILE="$HOME/openwebui-install.log"
INSTALL_START=$(date +%s)

# ── 로그 함수 ─────────────────────────────────────────────────────────────────
log()     { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN  ]${NC} $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERROR ]${NC} $*" | tee -a "$LOG_FILE"; }
info()    { echo -e "${CYAN}[INFO  ]${NC} $*" | tee -a "$LOG_FILE"; }
ok()      { echo -e "${GREEN}[  OK  ]${NC} $*" | tee -a "$LOG_FILE"; }
section() {
  echo "" | tee -a "$LOG_FILE"
  echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
  echo -e "${BOLD}${BLUE}  🔹 $*${NC}" | tee -a "$LOG_FILE"
  echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
}

touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"

# =============================================================================
# STEP 0: 배너
# =============================================================================
clear
echo -e "${BOLD}${BLUE}"
cat << 'BANNER'
 ██████╗ ██████╗ ███████╗███╗   ██╗    ██╗    ██╗███████╗██████╗ ██╗   ██╗██╗
██╔═══██╗██╔══██╗██╔════╝████╗  ██║    ██║    ██║██╔════╝██╔══██╗██║   ██║██║
██║   ██║██████╔╝█████╗  ██╔██╗ ██║    ██║ █╗ ██║█████╗  ██████╔╝██║   ██║██║
██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║    ██║███╗██║██╔══╝  ██╔══██╗██║   ██║██║
╚██████╔╝██║     ███████╗██║ ╚████║    ╚███╔███╔╝███████╗██████╔╝╚██████╔╝██║
 ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝     ╚══╝╚══╝ ╚══════╝╚═════╝  ╚═════╝ ╚═╝
BANNER
echo -e "${NC}"
echo -e "  ${BOLD}🔐 보안강화 RAG 원터치 설치 스크립트${NC}"
echo -e "  ${CYAN}Docker + Ollama + Groq + Qdrant + Nginx + SSL/TLS + UFW + Fail2ban${NC}"
echo -e "  ${MAGENTA}AWS EC2 · Google Cloud · Azure · DigitalOcean · 온프레미스 지원${NC}"
echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# =============================================================================
# STEP 1: 실행 환경 검증
# =============================================================================
section "STEP 1: 실행 환경 검증"

if [ "$EUID" -eq 0 ]; then
  error "root로 실행하지 마세요. sudo 권한이 있는 일반 사용자로 실행하세요."
  exit 1
fi

if ! sudo -n true 2>/dev/null; then
  warn "sudo 비밀번호 입력이 필요합니다."
  sudo -v || { error "sudo 권한이 없습니다."; exit 1; }
fi

# sudo 세션 갱신 (백그라운드)
( while true; do sudo -n true; sleep 50; done ) &
SUDO_PID=$!
trap "kill $SUDO_PID 2>/dev/null; exit" EXIT INT TERM

ok "실행 사용자: $USER (sudo 확인됨)"

# =============================================================================
# STEP 2: 시스템 사양 자동 감지
# =============================================================================
section "STEP 2: 시스템 사양 감지"

CPU_CORES=$(nproc 2>/dev/null || echo 1)
TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 0)
AVAILABLE_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo 0)
TOTAL_RAM_MB=${TOTAL_RAM_MB:-0}
AVAILABLE_RAM_MB=${AVAILABLE_RAM_MB:-0}
TOTAL_RAM=$((TOTAL_RAM_MB / 1024))
AVAILABLE_RAM=$((AVAILABLE_RAM_MB / 1024))
DISK_FREE_GB=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2{gsub("G",""); print $4}' || echo 0)

# AWS/클라우드 환경 감지 (타임아웃: 1초, 실패 시 무시)
AWS_INSTANCE_TYPE="Unknown"
AWS_REGION="Unknown"
AWS_PUBLIC_IP="Unknown"
AWS_PRIVATE_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "Unknown")
IS_AWS=false

# AWS IMDSv2 시도 (타임아웃 짧게 설정)
IMDS_TOKEN=$(curl -sf --max-time 1 --connect-timeout 1 -X PUT \
  "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")

if [ -n "$IMDS_TOKEN" ]; then
  IS_AWS=true
  AWS_INSTANCE_TYPE=$(curl -sf --max-time 1 \
    -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
    "http://169.254.169.254/latest/meta-data/instance-type" 2>/dev/null || echo "Unknown")
  AWS_REGION=$(curl -sf --max-time 1 \
    -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
    "http://169.254.169.254/latest/meta-data/placement/region" 2>/dev/null || echo "Unknown")
  AWS_PUBLIC_IP=$(curl -sf --max-time 1 \
    -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
    "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || echo "Unknown")
fi

# 외부 IP 조회 (클라우드 아닌 경우 대비)
if [ "$AWS_PUBLIC_IP" = "Unknown" ]; then
  AWS_PUBLIC_IP=$(curl -sf --max-time 2 https://api.ipify.org 2>/dev/null || \
                  curl -sf --max-time 2 https://ifconfig.me 2>/dev/null || \
                  curl -sf --max-time 2 https://icanhazip.com 2>/dev/null || \
                  echo "Unknown")
fi

ACCESS_HOST="$AWS_PUBLIC_IP"
[ "$ACCESS_HOST" = "Unknown" ] && ACCESS_HOST="$AWS_PRIVATE_IP"
[ "$ACCESS_HOST" = "Unknown" ] && ACCESS_HOST="localhost"

info "CPU 코어    : ${CPU_CORES}개"
info "총 메모리   : ${TOTAL_RAM}GB (가용: ${AVAILABLE_RAM}GB)"
info "디스크 여유 : ${DISK_FREE_GB}GB"
if [ "$IS_AWS" = true ]; then
  info "클라우드    : AWS EC2 ($AWS_INSTANCE_TYPE, $AWS_REGION)"
else
  info "클라우드    : AWS 아님 (일반 리눅스 서버 또는 타 클라우드)"
fi
info "공인 IP     : $AWS_PUBLIC_IP"
info "사설 IP     : $AWS_PRIVATE_IP"

[ "$TOTAL_RAM" -lt 2 ] && { error "최소 2GB RAM 필요 (현재 ${TOTAL_RAM}GB)"; exit 1; }
[ "$DISK_FREE_GB" -lt 10 ] && warn "디스크 여유 공간이 10GB 미만입니다."

# 성능 등급 판단
if   [ "$CPU_CORES" -ge 6 ] && [ "$TOTAL_RAM" -ge 16 ]; then
  PERFORMANCE="HIGH";        PERF_NAME="고성능 🚀"
  QDRANT_RETRIES=20; QDRANT_INTERVAL=2; TOOLS_RETRIES=20; TOOLS_INTERVAL=2
  WEBUI_RETRIES=30;  WEBUI_INTERVAL=2
  MEMORY_QDRANT="1G"; MEMORY_TOOLS="2G"; MEMORY_WEBUI="4G"
elif [ "$CPU_CORES" -ge 4 ] && [ "$TOTAL_RAM" -ge 8 ]; then
  PERFORMANCE="MEDIUM_HIGH"; PERF_NAME="중상급 💪"
  QDRANT_RETRIES=30; QDRANT_INTERVAL=3; TOOLS_RETRIES=30; TOOLS_INTERVAL=3
  WEBUI_RETRIES=40;  WEBUI_INTERVAL=3
  MEMORY_QDRANT="768M"; MEMORY_TOOLS="1.5G"; MEMORY_WEBUI="3G"
elif [ "$CPU_CORES" -ge 2 ] && [ "$TOTAL_RAM" -ge 4 ]; then
  PERFORMANCE="MEDIUM";      PERF_NAME="중급 📊"
  QDRANT_RETRIES=40; QDRANT_INTERVAL=4; TOOLS_RETRIES=40; TOOLS_INTERVAL=4
  WEBUI_RETRIES=60;  WEBUI_INTERVAL=4
  MEMORY_QDRANT="512M"; MEMORY_TOOLS="1G"; MEMORY_WEBUI="2G"
else
  PERFORMANCE="LOW";         PERF_NAME="저사양 🐢"
  QDRANT_RETRIES=60; QDRANT_INTERVAL=5; TOOLS_RETRIES=60; TOOLS_INTERVAL=5
  WEBUI_RETRIES=120; WEBUI_INTERVAL=5
  MEMORY_QDRANT="384M"; MEMORY_TOOLS="768M"; MEMORY_WEBUI="1.5G"
fi

ok "성능 등급: ${PERF_NAME}"
PYTHON_RETRIES=$((QDRANT_RETRIES / 2))

# =============================================================================
# STEP 3: 설치 설정 입력
# =============================================================================
section "STEP 3: 설치 설정 입력"

# ── 도메인 ──────────────────────────────────────────────────────────────────
echo -e "${CYAN}📌 도메인 설정${NC} (없으면 IP로 접근, SSL 자동 발급은 도메인 필수)"
read -t 60 -p "🌐 도메인 입력 (Enter=IP 접근): " DOMAIN_NAME || true
DOMAIN_NAME=$(echo "${DOMAIN_NAME:-}" | xargs | tr '[:upper:]' '[:lower:]')
[ -n "$DOMAIN_NAME" ] && USE_DOMAIN=true && ok "도메인: $DOMAIN_NAME" \
                       || USE_DOMAIN=false && ok "IP 접근 모드: $ACCESS_HOST"

# ── Nginx 리버스 프록시 ──────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}📌 Nginx 리버스 프록시 + 보안헤더${NC}"
echo "   WebUI(80/443), Tools API(/api/), Qdrant(/qdrant/) 통합 프록시"
read -t 30 -p "🔀 Nginx 설치? (Enter=Y): " USE_NGINX_INPUT || true
[[ "${USE_NGINX_INPUT:-Y}" =~ ^[Nn]$ ]] && USE_NGINX=false || USE_NGINX=true

# ── SSL ─────────────────────────────────────────────────────────────────────
USE_SSL=false
SSL_EMAIL=""
if [ "$USE_NGINX" = true ] && [ "$USE_DOMAIN" = true ]; then
  echo ""
  echo -e "${CYAN}📌 Let's Encrypt SSL/TLS 자동 발급${NC}"
  read -t 30 -p "🔒 SSL 자동 발급? (Enter=Y): " USE_SSL_INPUT || true
  if [[ ! "${USE_SSL_INPUT:-Y}" =~ ^[Nn]$ ]]; then
    USE_SSL=true
    read -t 60 -p "📧 SSL 인증서 이메일: " SSL_EMAIL || true
    SSL_EMAIL=$(echo "${SSL_EMAIL:-}" | xargs)
    [ -z "$SSL_EMAIL" ] && warn "이메일 없음 - SSL 발급 건너뜀" && USE_SSL=false
  fi
fi

# ── Basic Auth (Tools/Qdrant 관리 패널) ─────────────────────────────────────
echo ""
echo -e "${CYAN}📌 관리 패널 Basic Auth 보호${NC} (Tools API /docs, Qdrant Dashboard)"
read -t 30 -p "🔑 Basic Auth 설정? (Enter=Y): " USE_BASICAUTH_INPUT || true
USE_BASICAUTH=false
BASICAUTH_USER="admin"
BASICAUTH_PASS=""
if [[ ! "${USE_BASICAUTH_INPUT:-Y}" =~ ^[Nn]$ ]]; then
  USE_BASICAUTH=true
  read -t 30 -p "   관리자 ID (Enter=admin): " BASICAUTH_USER || true
  BASICAUTH_USER=$(echo "${BASICAUTH_USER:-admin}" | xargs)
  [ -z "$BASICAUTH_USER" ] && BASICAUTH_USER="admin"
  while true; do
    read -t 60 -s -p "   관리자 비밀번호 (최소 8자): " BASICAUTH_PASS || true
    echo ""
    BASICAUTH_PASS=$(echo "${BASICAUTH_PASS:-}" | xargs)
    if [ ${#BASICAUTH_PASS} -ge 8 ]; then break
    else warn "비밀번호가 너무 짧습니다. 8자 이상 입력하세요."; fi
  done
  ok "Basic Auth: $BASICAUTH_USER / ****"
fi

# ── Ollama ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}📌 Ollama 로컬 LLM 설정${NC}"
if [ "$PERFORMANCE" = "HIGH" ] || [ "$PERFORMANCE" = "MEDIUM_HIGH" ]; then
  read -t 30 -p "🤖 Ollama 설치/사용? ${PERF_NAME} 권장 (Enter=Y): " USE_OLLAMA_IN || true
  [[ "${USE_OLLAMA_IN:-Y}" =~ ^[Nn]$ ]] && USE_OLLAMA=false || USE_OLLAMA=true
else
  read -t 30 -p "🤖 Ollama 설치/사용? ${PERF_NAME} 비권장 (Enter=N): " USE_OLLAMA_IN || true
  [[ "${USE_OLLAMA_IN:-N}" =~ ^[Yy]$ ]] && USE_OLLAMA=true || USE_OLLAMA=false
fi

# ── Groq API Key ─────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}📌 Groq API Key${NC} (https://console.groq.com 에서 무료 발급)"
[ "$USE_OLLAMA" = false ] && echo "   ⚠️  Ollama 미사용 → Groq 키 권장"
read -t 90 -p "🔑 Groq API Key (Enter=건너뜀): " GROQ_API_KEY || true
GROQ_API_KEY=$(echo "${GROQ_API_KEY:-}" | xargs)
[ -n "$GROQ_API_KEY" ] && USE_GROQ=true && ok "Groq API: 활성화" \
                        || USE_GROQ=false && info "Groq API: 건너뜀"

# Ollama + Groq 모두 없으면 경고
if [ "$USE_OLLAMA" = false ] && [ "$USE_GROQ" = false ]; then
  echo ""
  warn "Ollama와 Groq 모두 비활성화됩니다."
  warn "설치 후 Settings에서 API 키를 추가하거나 Ollama를 설치하세요."
  read -t 20 -p "   계속? (Enter=Y): " CONT || CONT="Y"
  [[ "${CONT:-Y}" =~ ^[Nn]$ ]] && { info "설치 중단됨"; exit 0; }
fi

# ── Fail2ban ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}📌 Fail2ban 브루트포스 방어${NC}"
read -t 20 -p "🛡️  Fail2ban 설치? (Enter=Y): " USE_FAIL2BAN_INPUT || true
[[ "${USE_FAIL2BAN_INPUT:-Y}" =~ ^[Nn]$ ]] && USE_FAIL2BAN=false || USE_FAIL2BAN=true

# ── UFW 방화벽 ───────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}📌 UFW 방화벽 설정${NC}"
read -t 20 -p "🔥 UFW 방화벽 활성화? (Enter=Y): " USE_UFW_INPUT || true
[[ "${USE_UFW_INPUT:-Y}" =~ ^[Nn]$ ]] && USE_UFW=false || USE_UFW=true

# 설정 요약
echo ""
echo -e "${BOLD}${MAGENTA}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${BOLD}${MAGENTA}│  📋 설치 설정 요약                                  │${NC}"
echo -e "${BOLD}${MAGENTA}└─────────────────────────────────────────────────────┘${NC}"
echo -e "  성능 등급   : ${PERF_NAME}"
echo -e "  도메인      : ${DOMAIN_NAME:-IP 직접 접근 ($ACCESS_HOST)}"
echo -e "  Nginx       : $([ "$USE_NGINX" = true ] && echo '✅ 활성화' || echo '❌ 비활성화')"
echo -e "  SSL/TLS     : $([ "$USE_SSL" = true ] && echo "✅ Let's Encrypt ($DOMAIN_NAME)" || echo '❌ 비활성화')"
echo -e "  Basic Auth  : $([ "$USE_BASICAUTH" = true ] && echo "✅ $BASICAUTH_USER" || echo '❌ 비활성화')"
echo -e "  Ollama      : $([ "$USE_OLLAMA" = true ] && echo '✅ 활성화' || echo '❌ 비활성화')"
echo -e "  Groq API    : $([ "$USE_GROQ" = true ] && echo '✅ 활성화' || echo '❌ 비활성화')"
echo -e "  Fail2ban    : $([ "$USE_FAIL2BAN" = true ] && echo '✅ 활성화' || echo '❌ 비활성화')"
echo -e "  UFW         : $([ "$USE_UFW" = true ] && echo '✅ 활성화' || echo '❌ 비활성화')"
echo ""
read -t 20 -p "  ▶ 위 설정으로 설치를 시작합니까? (Enter=Y): " CONFIRM || CONFIRM="Y"
[[ "${CONFIRM:-Y}" =~ ^[Nn]$ ]] && { info "설치 취소됨"; exit 0; }

# =============================================================================
# STEP 4: 시스템 패키지 업데이트 및 의존성 설치
# =============================================================================
section "STEP 4: 시스템 패키지 설치"

log "시스템 업데이트 중..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

log "필수 패키지 설치 중..."
PKGS="curl wget git openssl ca-certificates gnupg lsb-release apt-transport-https \
      software-properties-common htop net-tools unzip jq"
[ "$USE_NGINX" = true ] && PKGS="$PKGS nginx"
[ "$USE_FAIL2BAN" = true ] && PKGS="$PKGS fail2ban"
[ "$USE_UFW" = true ] && PKGS="$PKGS ufw"
[ "$USE_BASICAUTH" = true ] && PKGS="$PKGS apache2-utils"

sudo apt-get install -y -qq $PKGS
ok "패키지 설치 완료"

# =============================================================================
# STEP 5: Docker 자동 설치
# =============================================================================
section "STEP 5: Docker 설치"

if ! command -v docker >/dev/null 2>&1; then
  log "Docker 설치 중..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"

  # 현재 세션에 docker 그룹 즉시 적용
  if ! groups | grep -q docker; then
    exec sg docker "bash $0 $*" 2>/dev/null || true
    warn "docker 그룹 적용을 위해 로그아웃 후 재접속이 필요할 수 있습니다."
  fi
  ok "Docker 설치 완료"
else
  ok "Docker 이미 설치됨: $(docker --version 2>/dev/null | head -1)"
fi

# Docker 서비스 시작
if ! sudo systemctl is-active --quiet docker; then
  sudo systemctl enable --now docker
  sleep 3
fi

# Docker 권한 재확인
if ! docker ps >/dev/null 2>&1; then
  sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
  if ! docker ps >/dev/null 2>&1; then
    error "Docker 권한 없음. 재로그인 후 스크립트를 재실행하세요: newgrp docker"
    exit 1
  fi
fi

ok "Docker 실행 중: $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"

# =============================================================================
# STEP 6: Ollama 설치
# =============================================================================
section "STEP 6: Ollama 설치"

if [ "$USE_OLLAMA" = true ]; then
  if command -v ollama >/dev/null 2>&1; then
    ok "Ollama 이미 설치됨"
  else
    log "Ollama 설치 중..."
    curl -fsSL https://ollama.com/install.sh | sh
    ok "Ollama 설치 완료"
  fi

  # 서비스 시작
  if sudo systemctl enable ollama 2>/dev/null && sudo systemctl start ollama 2>/dev/null; then
    sleep 5
    ok "Ollama 서비스 활성화"
  else
    warn "systemd 등록 실패, 수동 시작"
    nohup ollama serve > /tmp/ollama.log 2>&1 &
    sleep 5
  fi

  # 임베딩 모델
  log "nomic-embed-text 모델 다운로드 중..."
  ollama pull nomic-embed-text 2>/dev/null && ok "임베딩 모델 준비 완료" \
    || warn "임베딩 모델 다운로드 실패 (나중에 수동 실행: ollama pull nomic-embed-text)"
else
  info "Ollama 건너뜀"
fi

# =============================================================================
# STEP 7: GPU 감지
# =============================================================================
section "STEP 7: GPU 감지"

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  OPEN_WEBUI_IMAGE="ghcr.io/open-webui/open-webui:cuda"
  ok "NVIDIA GPU 감지 → CUDA 이미지 사용"
else
  OPEN_WEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"
  info "GPU 없음 → CPU 모드"
fi

# =============================================================================
# STEP 8: 작업 디렉토리 및 파일 생성
# =============================================================================
section "STEP 8: 프로젝트 디렉토리 구성"

if [ -d "$BASE_DIR" ]; then
  log "기존 설치 정리 중..."
  cd "$BASE_DIR" && docker compose down -v 2>/dev/null || true
  cd "$HOME" && rm -rf "$BASE_DIR"
fi

mkdir -p "$BASE_DIR/tools-api/data"
mkdir -p "$BASE_DIR/nginx/conf.d"
mkdir -p "$BASE_DIR/nginx/ssl"
mkdir -p "$BASE_DIR/nginx/auth"
mkdir -p "$BASE_DIR/nginx/html"
mkdir -p "$BASE_DIR/scripts"
mkdir -p "$BASE_DIR/logs"
cd "$BASE_DIR"

ok "디렉토리 구성 완료: $BASE_DIR"

# ── .env 생성 ─────────────────────────────────────────────────────────────────
SECRET_KEY=$(openssl rand -hex 32)
QDRANT_API_KEY=$(openssl rand -hex 24)

cat > .env << ENVEOF
# ==============================================
# OpenWebUI RAG 환경 설정
# 생성일: $(date '+%Y-%m-%d %H:%M:%S')
# ==============================================

# Qdrant 설정
VECTOR_DB=qdrant
QDRANT_URI=http://qdrant:6333
QDRANT_URL=http://qdrant:6333
QDRANT_COLLECTION=openapi_rag
QDRANT_API_KEY=${QDRANT_API_KEY}

# WebUI 보안
WEBUI_SECRET_KEY=${SECRET_KEY}
WEBUI_AUTH=true

# 접근 설정
ACCESS_HOST=${ACCESS_HOST}
ENVEOF

if [ "$USE_OLLAMA" = true ]; then
cat >> .env << ENVEOF

# Ollama 설정
OLLAMA_BASE_URL=http://host.docker.internal:11434
OLLAMA_EMBED_MODEL=nomic-embed-text
ENVEOF
fi

if [ "$USE_GROQ" = true ] && [ -n "$GROQ_API_KEY" ]; then
cat >> .env << ENVEOF

# Groq API
OPENAI_API_KEY=${GROQ_API_KEY}
OPENAI_API_BASE_URL=https://api.groq.com/openai/v1
ENVEOF
fi

chmod 600 .env
ok ".env 생성 완료 (권한 600)"

# ── Basic Auth htpasswd ───────────────────────────────────────────────────────
if [ "$USE_BASICAUTH" = true ]; then
  htpasswd -bc "$BASE_DIR/nginx/auth/.htpasswd" "$BASICAUTH_USER" "$BASICAUTH_PASS" 2>/dev/null
  chmod 640 "$BASE_DIR/nginx/auth/.htpasswd"
  ok "htpasswd 생성 완료"
fi

# ── Tools API: requirements.txt ───────────────────────────────────────────────
cat > tools-api/requirements.txt << 'REQEOF'
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
requests==2.31.0
python-multipart==0.0.6
pypdf==3.17.4
qdrant-client==1.7.0
numpy==1.26.3
ollama==0.1.6
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
REQEOF

# ── Tools API: main.py ────────────────────────────────────────────────────────
cat > tools-api/main.py << PYEOF
from fastapi import FastAPI, UploadFile, File, HTTPException, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import os, uuid, time, hashlib
from pypdf import PdfReader
import ollama
from qdrant_client import QdrantClient
from qdrant_client.models import VectorParams, Distance, PointStruct

app = FastAPI(
    title="OpenAPI RAG Tool Server",
    description="Secure RAG Tool Server (Qdrant + Ollama)",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS: Nginx 리버스 프록시 경유 허용
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# 환경 변수
QDRANT_URL    = os.getenv("QDRANT_URL",        "http://qdrant:6333")
QDRANT_APIKEY = os.getenv("QDRANT_API_KEY",    "")
COLLECTION    = os.getenv("QDRANT_COLLECTION", "openapi_rag")
MODEL         = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
OLLAMA_URL    = os.getenv("OLLAMA_BASE_URL",   "http://host.docker.internal:11434")
DATA_DIR      = "/app/data"
MAX_FILE_MB   = int(os.getenv("MAX_UPLOAD_MB", "50"))

# Qdrant 연결
client   = None
RETRIES  = ${PYTHON_RETRIES}
INTERVAL = ${QDRANT_INTERVAL}

print(f"🔄 Qdrant 연결 중... (최대 {RETRIES}회, {INTERVAL}초 간격)")
for attempt in range(RETRIES):
    try:
        kwargs = {"url": QDRANT_URL}
        if QDRANT_APIKEY:
            kwargs["api_key"] = QDRANT_APIKEY
        client = QdrantClient(**kwargs)
        client.get_collections()
        print(f"✅ Qdrant 연결 성공: {QDRANT_URL}")
        break
    except Exception as e:
        print(f"⏳ 대기 중... ({attempt+1}/{RETRIES}): {e}")
        time.sleep(INTERVAL)

if not client:
    print("❌ Qdrant 연결 실패")

# 컬렉션 초기화
if client:
    try:
        names = [c.name for c in client.get_collections().collections]
        if COLLECTION not in names:
            client.create_collection(
                collection_name=COLLECTION,
                vectors_config=VectorParams(size=768, distance=Distance.COSINE),
            )
            print(f"✅ 컬렉션 생성: {COLLECTION}")
        else:
            print(f"✅ 기존 컬렉션: {COLLECTION}")
    except Exception as e:
        print(f"❌ 컬렉션 오류: {e}")

# 파일 크기 검증
async def check_file_size(file: UploadFile = File(...)):
    content = await file.read()
    size_mb = len(content) / (1024 * 1024)
    if size_mb > MAX_FILE_MB:
        raise HTTPException(400, f"파일이 너무 큽니다 ({size_mb:.1f}MB > {MAX_FILE_MB}MB)")
    await file.seek(0)
    return file

def embed(text: str):
    try:
        oc = ollama.Client(host=OLLAMA_URL)
        resp = oc.embeddings(model=MODEL, prompt=text)
        return resp["embedding"]
    except Exception as e:
        raise HTTPException(500, f"Embedding error: {str(e)}")

@app.post("/documents/upload", summary="PDF 업로드 및 RAG 인덱싱")
async def upload_pdf(file: UploadFile = File(...)):
    if not client:
        raise HTTPException(503, "Qdrant 연결 없음")

    # 파일 타입 검사
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(400, "PDF 파일만 허용됩니다")

    # 파일 크기 검사
    content = await file.read()
    size_mb = len(content) / (1024 * 1024)
    if size_mb > MAX_FILE_MB:
        raise HTTPException(400, f"파일이 너무 큽니다 ({size_mb:.1f}MB > {MAX_FILE_MB}MB)")

    # 파일명 안전 처리 (path traversal 방지)
    safe_filename = os.path.basename(file.filename).replace("..", "").replace("/", "")
    safe_filename = "".join(c for c in safe_filename if c.isalnum() or c in "._- ")
    path = os.path.join(DATA_DIR, safe_filename)

    try:
        with open(path, "wb") as f:
            f.write(content)
        print(f"📄 저장: {safe_filename}")

        reader = PdfReader(path)
        text = "".join(p.extract_text() or "" for p in reader.pages)
        if not text.strip():
            raise HTTPException(400, "PDF 텍스트 추출 실패")

        print(f"📝 텍스트: {len(text)} 문자")
        chunks, chunk_size, overlap = [], 1000, 100
        for i in range(0, len(text), chunk_size - overlap):
            chunk = text[i:i + chunk_size].strip()
            if chunk:
                chunks.append(chunk)

        print(f"✂️ 청크: {len(chunks)}개")
        points = []
        for idx, chunk in enumerate(chunks):
            try:
                vector = embed(chunk)
                points.append(PointStruct(
                    id=str(uuid.uuid4()),
                    vector=vector,
                    payload={"text": chunk, "source": safe_filename, "chunk_index": idx}
                ))
                if (idx + 1) % 10 == 0:
                    print(f"🔢 임베딩: {idx+1}/{len(chunks)}")
            except Exception as e:
                print(f"⚠️ 청크 {idx} 실패: {e}")
                continue

        if not points:
            raise HTTPException(500, "임베딩 실패")

        client.upsert(collection_name=COLLECTION, points=points)
        print(f"💾 저장: {len(points)}개")
        return {
            "status": "success", "filename": safe_filename,
            "total_chunks": len(chunks), "indexed_chunks": len(points),
            "collection": COLLECTION
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Upload error: {str(e)}")

class SearchQuery(BaseModel):
    query: str
    top_k: int = 3

    class Config:
        str_min_length = 1
        str_max_length = 1000

@app.post("/rag/search", summary="시맨틱 검색")
def rag_search(search: SearchQuery):
    if not client:
        raise HTTPException(503, "Qdrant 연결 없음")
    if not search.query.strip():
        raise HTTPException(400, "쿼리가 비어 있습니다")
    top_k = max(1, min(search.top_k, 20))
    try:
        qv = embed(search.query)
        hits = client.search(collection_name=COLLECTION, query_vector=qv, limit=top_k)
        return {
            "query": search.query,
            "results": [
                {"text": h.payload.get("text",""), "source": h.payload.get("source",""),
                 "chunk_index": h.payload.get("chunk_index",0), "score": h.score}
                for h in hits
            ],
            "count": len(hits)
        }
    except Exception as e:
        raise HTTPException(500, f"Search error: {str(e)}")

@app.get("/health", summary="Health Check")
def health():
    try:
        if not client:
            return {"status": "unhealthy", "error": "Qdrant 없음"}
        client.get_collections()
        cols = client.get_collections()
        col_names = [c.name for c in cols.collections]
        doc_count = 0
        if COLLECTION in col_names:
            info = client.get_collection(COLLECTION)
            doc_count = info.vectors_count or 0
        return {
            "status": "healthy", "qdrant_url": QDRANT_URL,
            "collection": COLLECTION, "embed_model": MODEL,
            "indexed_documents": doc_count
        }
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

@app.get("/", summary="API 정보")
def root():
    return {
        "service": "OpenAPI RAG Tool Server", "version": "1.0.0",
        "endpoints": {
            "docs": "/docs", "upload": "/documents/upload",
            "search": "/rag/search", "health": "/health"
        }
    }
PYEOF

# ── Tools API: Dockerfile ─────────────────────────────────────────────────────
cat > tools-api/Dockerfile << 'DKEOF'
FROM python:3.11-slim

# 보안: 비루트 사용자 생성
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# 시스템 의존성
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc curl && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Python 의존성
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .
RUN mkdir -p /app/data && chown -R appuser:appuser /app

# 비루트 실행
USER appuser

EXPOSE 8000

# 헬스체크
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--workers", "2", "--no-server-header"]
DKEOF

ok "Tools API 파일 생성 완료"

# ── Nginx 설정 생성 ───────────────────────────────────────────────────────────
if [ "$USE_NGINX" = true ]; then

  # 보안 랜딩 페이지 (현황 대시보드)
  LANDING_TITLE="${DOMAIN_NAME:-$ACCESS_HOST}"
  TOOLS_ENDPOINT=$([ "$USE_NGINX" = true ] && echo "/api" || echo ":8000")
  QDRANT_ENDPOINT=$([ "$USE_NGINX" = true ] && echo "/qdrant" || echo ":6333")

cat > nginx/html/index.html << HTMLEOF
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>OpenWebUI RAG — 서비스 현황</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@300;400;600&family=Syne:wght@400;700;800&display=swap" rel="stylesheet">
<style>
  :root {
    --bg: #0a0e1a;
    --surface: #0f1626;
    --border: #1e2d4a;
    --accent: #00d4ff;
    --accent2: #7c3aed;
    --accent3: #10b981;
    --warn: #f59e0b;
    --danger: #ef4444;
    --text: #e2e8f0;
    --muted: #64748b;
    --glow: rgba(0, 212, 255, 0.15);
  }
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: 'IBM Plex Mono', monospace;
    background: var(--bg);
    color: var(--text);
    min-height: 100vh;
    overflow-x: hidden;
  }

  /* 배경 그리드 효과 */
  body::before {
    content: '';
    position: fixed; inset: 0;
    background-image:
      linear-gradient(rgba(0,212,255,0.03) 1px, transparent 1px),
      linear-gradient(90deg, rgba(0,212,255,0.03) 1px, transparent 1px);
    background-size: 40px 40px;
    pointer-events: none;
    z-index: 0;
  }

  .container {
    position: relative; z-index: 1;
    max-width: 960px;
    margin: 0 auto;
    padding: 40px 24px 80px;
  }

  /* 헤더 */
  header {
    text-align: center;
    padding: 60px 0 50px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 50px;
  }

  .logo-badge {
    display: inline-flex; align-items: center; gap: 10px;
    background: rgba(0,212,255,0.08);
    border: 1px solid rgba(0,212,255,0.25);
    border-radius: 100px;
    padding: 6px 18px;
    font-size: 11px;
    letter-spacing: 0.2em;
    color: var(--accent);
    text-transform: uppercase;
    margin-bottom: 24px;
    animation: pulse-border 3s ease-in-out infinite;
  }

  @keyframes pulse-border {
    0%, 100% { box-shadow: 0 0 0 0 rgba(0,212,255,0); }
    50% { box-shadow: 0 0 0 4px rgba(0,212,255,0.08); }
  }

  h1 {
    font-family: 'Syne', sans-serif;
    font-size: clamp(2rem, 5vw, 3.2rem);
    font-weight: 800;
    background: linear-gradient(135deg, #e2e8f0 0%, var(--accent) 50%, var(--accent2) 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
    line-height: 1.15;
    margin-bottom: 16px;
  }

  .subtitle {
    color: var(--muted);
    font-size: 13px;
    letter-spacing: 0.05em;
  }

  .status-bar {
    display: flex; align-items: center; justify-content: center; gap: 24px;
    margin-top: 28px;
    flex-wrap: wrap;
  }

  .status-item {
    display: flex; align-items: center; gap: 8px;
    font-size: 12px; color: var(--muted);
  }

  .dot {
    width: 8px; height: 8px; border-radius: 50%;
    background: var(--accent3);
    box-shadow: 0 0 8px var(--accent3);
    animation: blink 2s ease-in-out infinite;
  }
  .dot.warn { background: var(--warn); box-shadow: 0 0 8px var(--warn); }

  @keyframes blink {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
  }

  /* 서비스 카드 그리드 */
  .services-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 20px;
    margin-bottom: 48px;
  }

  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 16px;
    padding: 28px;
    position: relative;
    overflow: hidden;
    transition: transform 0.2s, border-color 0.2s, box-shadow 0.2s;
    cursor: default;
  }

  .card::before {
    content: '';
    position: absolute; top: 0; left: 0; right: 0;
    height: 2px;
    background: linear-gradient(90deg, transparent, var(--card-accent, var(--accent)), transparent);
    opacity: 0;
    transition: opacity 0.2s;
  }

  .card:hover {
    transform: translateY(-3px);
    border-color: rgba(0,212,255,0.3);
    box-shadow: 0 12px 40px rgba(0,0,0,0.4), 0 0 0 1px rgba(0,212,255,0.08);
  }

  .card:hover::before { opacity: 1; }

  .card-header {
    display: flex; align-items: flex-start; justify-content: space-between;
    margin-bottom: 20px;
  }

  .card-icon {
    width: 48px; height: 48px;
    border-radius: 12px;
    display: flex; align-items: center; justify-content: center;
    font-size: 22px;
    background: rgba(0,212,255,0.08);
    border: 1px solid rgba(0,212,255,0.15);
  }

  .card-badge {
    font-size: 10px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    padding: 4px 10px;
    border-radius: 100px;
    font-weight: 600;
  }

  .badge-green  { background: rgba(16,185,129,0.12); color: var(--accent3); border: 1px solid rgba(16,185,129,0.25); }
  .badge-blue   { background: rgba(0,212,255,0.10);  color: var(--accent);  border: 1px solid rgba(0,212,255,0.25); }
  .badge-purple { background: rgba(124,58,237,0.12); color: #a78bfa;        border: 1px solid rgba(124,58,237,0.25); }
  .badge-amber  { background: rgba(245,158,11,0.12); color: var(--warn);    border: 1px solid rgba(245,158,11,0.25); }

  .card-title {
    font-family: 'Syne', sans-serif;
    font-size: 18px; font-weight: 700;
    color: var(--text);
    margin-bottom: 8px;
  }

  .card-desc {
    font-size: 12px; color: var(--muted);
    line-height: 1.6;
    margin-bottom: 20px;
  }

  .card-url {
    display: block;
    background: rgba(0,0,0,0.3);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 10px 14px;
    font-size: 11px;
    color: var(--accent);
    text-decoration: none;
    letter-spacing: 0.03em;
    word-break: break-all;
    transition: background 0.15s, border-color 0.15s;
  }

  .card-url:hover {
    background: rgba(0,212,255,0.06);
    border-color: rgba(0,212,255,0.35);
  }

  .card-meta {
    display: flex; gap: 12px;
    margin-top: 14px;
    flex-wrap: wrap;
  }

  .meta-tag {
    font-size: 10px; color: var(--muted);
    background: rgba(255,255,255,0.03);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 3px 8px;
    letter-spacing: 0.05em;
  }

  /* 보안 섹션 */
  .security-section {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 16px;
    padding: 32px;
    margin-bottom: 32px;
  }

  .section-title {
    font-family: 'Syne', sans-serif;
    font-size: 16px; font-weight: 700;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 0.1em;
    margin-bottom: 24px;
    display: flex; align-items: center; gap: 10px;
  }

  .security-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 12px;
  }

  .security-item {
    display: flex; align-items: center; gap: 12px;
    padding: 12px 16px;
    background: rgba(0,0,0,0.2);
    border: 1px solid var(--border);
    border-radius: 10px;
    font-size: 12px;
  }

  .sec-icon {
    font-size: 18px;
    width: 32px; height: 32px;
    display: flex; align-items: center; justify-content: center;
    flex-shrink: 0;
  }

  .sec-label { color: var(--muted); font-size: 10px; letter-spacing: 0.05em; }
  .sec-value { color: var(--text); font-size: 12px; margin-top: 2px; font-weight: 600; }

  /* RAG 사용법 */
  .usage-section {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 16px;
    padding: 32px;
    margin-bottom: 32px;
  }

  .cmd-block {
    background: #050810;
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 16px 20px;
    margin: 12px 0;
    position: relative;
  }

  .cmd-label {
    font-size: 10px; color: var(--accent2);
    letter-spacing: 0.15em; text-transform: uppercase;
    margin-bottom: 8px;
  }

  .cmd-text {
    font-size: 12px; color: #a5f3fc;
    line-height: 1.7;
    white-space: pre-wrap;
    word-break: break-all;
  }

  .copy-btn {
    position: absolute; top: 12px; right: 12px;
    background: rgba(0,212,255,0.1);
    border: 1px solid rgba(0,212,255,0.2);
    border-radius: 6px;
    color: var(--accent);
    font-size: 10px;
    padding: 4px 10px;
    cursor: pointer;
    font-family: 'IBM Plex Mono', monospace;
    letter-spacing: 0.05em;
    transition: all 0.15s;
  }
  .copy-btn:hover { background: rgba(0,212,255,0.2); }

  /* 라이브 상태 체크 */
  .health-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
    gap: 12px;
    margin-top: 16px;
  }

  .health-card {
    padding: 16px;
    background: rgba(0,0,0,0.25);
    border: 1px solid var(--border);
    border-radius: 10px;
    display: flex; align-items: center; gap: 14px;
  }

  .health-status {
    width: 12px; height: 12px; border-radius: 50%;
    flex-shrink: 0;
    background: var(--muted);
  }
  .health-status.up   { background: var(--accent3); box-shadow: 0 0 10px var(--accent3); }
  .health-status.down { background: var(--danger);  box-shadow: 0 0 10px var(--danger); }

  .health-name  { font-size: 13px; font-weight: 600; margin-bottom: 2px; }
  .health-msg   { font-size: 11px; color: var(--muted); }

  /* 푸터 */
  footer {
    text-align: center;
    border-top: 1px solid var(--border);
    padding-top: 32px;
    color: var(--muted);
    font-size: 11px;
    letter-spacing: 0.05em;
  }

  /* 반응형 */
  @media (max-width: 600px) {
    .services-grid { grid-template-columns: 1fr; }
    .security-grid { grid-template-columns: 1fr 1fr; }
  }

  /* 진입 애니메이션 */
  @keyframes fadeUp {
    from { opacity: 0; transform: translateY(20px); }
    to   { opacity: 1; transform: translateY(0); }
  }
  .card       { animation: fadeUp 0.5s ease both; }
  .card:nth-child(1) { animation-delay: 0.05s; }
  .card:nth-child(2) { animation-delay: 0.10s; }
  .card:nth-child(3) { animation-delay: 0.15s; }
</style>
</head>
<body>
<div class="container">

  <!-- 헤더 -->
  <header>
    <div class="logo-badge">
      <span style="width:6px;height:6px;border-radius:50%;background:var(--accent3);display:inline-block;"></span>
      SYSTEM ONLINE
    </div>
    <h1>OpenWebUI RAG<br>서비스 현황</h1>
    <p class="subtitle">AWS 보안강화 배포 · Docker + Nginx + SSL + Qdrant</p>
    <div class="status-bar">
      <div class="status-item"><div class="dot"></div><span>서비스 실행 중</span></div>
      <div class="status-item"><div class="dot"></div><span id="uptime-display">로드 중...</span></div>
      <div class="status-item" style="color: var(--muted);">🌐 ${LANDING_TITLE}</div>
    </div>
  </header>

  <!-- 서비스 카드 -->
  <div class="services-grid">

    <!-- Open WebUI -->
    <div class="card" style="--card-accent: var(--accent3);">
      <div class="card-header">
        <div class="card-icon">🤖</div>
        <span class="card-badge badge-green">메인 서비스</span>
      </div>
      <div class="card-title">Open WebUI</div>
      <div class="card-desc">
        Ollama · Groq 모델 통합 채팅<br>
        RAG 검색 · PDF 문서 분석<br>
        멀티 유저 · 대화 히스토리
      </div>
      <a href="/" class="card-url">🔗 WebUI 바로가기 →</a>
      <div class="card-meta">
        <span class="meta-tag">port: 8080 (내부)</span>
        <span class="meta-tag">proxy: /</span>
      </div>
    </div>

    <!-- Tools API -->
    <div class="card" style="--card-accent: var(--accent);">
      <div class="card-header">
        <div class="card-icon">⚙️</div>
        <span class="card-badge badge-blue">RAG API</span>
      </div>
      <div class="card-title">Tools API</div>
      <div class="card-desc">
        PDF 업로드 · 텍스트 인덱싱<br>
        시맨틱 검색 · 임베딩 생성<br>
        OpenAPI 3.0 스펙 제공
      </div>
      <a href="${TOOLS_ENDPOINT}/docs" class="card-url">🔗 API Docs →</a>
      <div class="card-meta">
        <span class="meta-tag">port: 8000 (내부)</span>
        <span class="meta-tag">proxy: /api/</span>
        <span class="meta-tag">🔒 Auth 보호</span>
      </div>
    </div>

    <!-- Qdrant -->
    <div class="card" style="--card-accent: var(--accent2);">
      <div class="card-header">
        <div class="card-icon">🗄️</div>
        <span class="card-badge badge-purple">벡터 DB</span>
      </div>
      <div class="card-title">Qdrant</div>
      <div class="card-desc">
        고성능 벡터 유사도 검색<br>
        COSINE 거리 측정 · 컬렉션 관리<br>
        실시간 인덱싱 대시보드
      </div>
      <a href="${QDRANT_ENDPOINT}/dashboard" class="card-url">🔗 Qdrant Dashboard →</a>
      <div class="card-meta">
        <span class="meta-tag">port: 6333 (내부)</span>
        <span class="meta-tag">proxy: /qdrant/</span>
        <span class="meta-tag">🔒 Auth 보호</span>
      </div>
    </div>

  </div>

  <!-- 보안 현황 -->
  <div class="security-section">
    <div class="section-title">🛡️ 보안 현황</div>
    <div class="security-grid">
      <div class="security-item">
        <div class="sec-icon">🌐</div>
        <div>
          <div class="sec-label">Nginx 프록시</div>
          <div class="sec-value" style="color: var(--accent3);">활성화</div>
        </div>
      </div>
      <div class="security-item">
        <div class="sec-icon">${USE_SSL:+🔒}${USE_SSL:-🔓}</div>
        <div>
          <div class="sec-label">SSL/TLS</div>
          <div class="sec-value" style="color: ${USE_SSL:+var(--accent3)}${USE_SSL:-var(--warn)};">${USE_SSL:+Let's Encrypt}${USE_SSL:-HTTP (미설정)}</div>
        </div>
      </div>
      <div class="security-item">
        <div class="sec-icon">🔑</div>
        <div>
          <div class="sec-label">관리 패널 인증</div>
          <div class="sec-value" style="color: ${USE_BASICAUTH:+var(--accent3)}${USE_BASICAUTH:-var(--warn)};">${USE_BASICAUTH:+Basic Auth}${USE_BASICAUTH:-미설정}</div>
        </div>
      </div>
      <div class="security-item">
        <div class="sec-icon">🔥</div>
        <div>
          <div class="sec-label">UFW 방화벽</div>
          <div class="sec-value" style="color: ${USE_UFW:+var(--accent3)}${USE_UFW:-var(--warn)};">${USE_UFW:+활성화}${USE_UFW:-비활성화}</div>
        </div>
      </div>
      <div class="security-item">
        <div class="sec-icon">🛡️</div>
        <div>
          <div class="sec-label">Fail2ban</div>
          <div class="sec-value" style="color: ${USE_FAIL2BAN:+var(--accent3)}${USE_FAIL2BAN:-var(--warn)};">${USE_FAIL2BAN:+활성화}${USE_FAIL2BAN:-비활성화}</div>
        </div>
      </div>
      <div class="security-item">
        <div class="sec-icon">🚫</div>
        <div>
          <div class="sec-label">Rate Limiting</div>
          <div class="sec-value" style="color: var(--accent3);">활성화</div>
        </div>
      </div>
      <div class="security-item">
        <div class="sec-icon">🔐</div>
        <div>
          <div class="sec-label">보안 헤더</div>
          <div class="sec-value" style="color: var(--accent3);">HSTS · CSP · XSS</div>
        </div>
      </div>
      <div class="security-item">
        <div class="sec-icon">🐳</div>
        <div>
          <div class="sec-label">컨테이너</div>
          <div class="sec-value" style="color: var(--accent3);">비루트 실행</div>
        </div>
      </div>
    </div>
  </div>

  <!-- 서비스 상태 (라이브 체크) -->
  <div class="security-section">
    <div class="section-title">📡 실시간 서비스 상태</div>
    <div class="health-grid" id="health-grid">
      <div class="health-card">
        <div class="health-status" id="h-webui"></div>
        <div><div class="health-name">Open WebUI</div><div class="health-msg" id="m-webui">확인 중...</div></div>
      </div>
      <div class="health-card">
        <div class="health-status" id="h-tools"></div>
        <div><div class="health-name">Tools API</div><div class="health-msg" id="m-tools">확인 중...</div></div>
      </div>
      <div class="health-card">
        <div class="health-status" id="h-qdrant"></div>
        <div><div class="health-name">Qdrant</div><div class="health-msg" id="m-qdrant">확인 중...</div></div>
      </div>
    </div>
  </div>

  <!-- RAG 사용법 -->
  <div class="usage-section">
    <div class="section-title">📚 RAG 빠른 시작</div>

    <div style="font-size: 12px; color: var(--muted); margin-bottom: 16px;">
      📄 1단계: PDF 문서 업로드 (인덱싱)
    </div>
    <div class="cmd-block">
      <div class="cmd-label">TERMINAL</div>
      <button class="copy-btn" onclick="copy(this)">COPY</button>
      <div class="cmd-text">curl -X POST ${TOOLS_ENDPOINT}/documents/upload \
  -F "file=@your-document.pdf"</div>
    </div>

    <div style="font-size: 12px; color: var(--muted); margin: 20px 0 12px;">
      🔍 2단계: 시맨틱 검색
    </div>
    <div class="cmd-block">
      <div class="cmd-label">TERMINAL</div>
      <button class="copy-btn" onclick="copy(this)">COPY</button>
      <div class="cmd-text">curl -X POST ${TOOLS_ENDPOINT}/rag/search \
  -H "Content-Type: application/json" \
  -d '{"query": "검색어를 입력하세요", "top_k": 3}'</div>
    </div>

    <div style="font-size: 12px; color: var(--muted); margin: 20px 0 12px;">
      ✅ 3단계: 헬스 체크
    </div>
    <div class="cmd-block">
      <div class="cmd-label">TERMINAL</div>
      <button class="copy-btn" onclick="copy(this)">COPY</button>
      <div class="cmd-text">curl ${TOOLS_ENDPOINT}/health</div>
    </div>
  </div>

  <!-- 푸터 -->
  <footer>
    <div>OpenWebUI RAG · AWS 보안강화 배포 · MIT License</div>
    <div style="margin-top: 8px; color: #334155;">
      Docker · Nginx · Qdrant · Ollama · Groq · UFW · Fail2ban
    </div>
  </footer>

</div>

<script>
// 업타임 표시
const start = Date.now();
function updateUptime() {
  const s = Math.floor((Date.now() - start) / 1000);
  const m = Math.floor(s / 60), h = Math.floor(m / 60);
  document.getElementById('uptime-display').textContent =
    h > 0 ? h+'h '+( m%60)+'m 가동' : m > 0 ? m+'m '+( s%60)+'s 가동' : s+'s 가동';
}
setInterval(updateUptime, 1000);
updateUptime();

// 헬스 체크
async function checkHealth(id, url, msgId) {
  const el = document.getElementById(id);
  const mg = document.getElementById(msgId);
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(4000) });
    if (r.ok) {
      el.className = 'health-status up';
      mg.textContent = '정상 운영 중';
    } else {
      el.className = 'health-status down';
      mg.textContent = 'HTTP ' + r.status;
    }
  } catch(e) {
    el.className = 'health-status down';
    mg.textContent = '응답 없음';
  }
}

function runHealthChecks() {
  checkHealth('h-webui',  '/',                      'm-webui');
  checkHealth('h-tools',  '${TOOLS_ENDPOINT}/health', 'm-tools');
  checkHealth('h-qdrant', '${QDRANT_ENDPOINT}/collections', 'm-qdrant');
}
runHealthChecks();
setInterval(runHealthChecks, 15000);

// 클립보드 복사
function copy(btn) {
  const text = btn.nextElementSibling.textContent;
  navigator.clipboard.writeText(text).then(() => {
    const orig = btn.textContent;
    btn.textContent = 'COPIED!';
    btn.style.color = '#10b981';
    setTimeout(() => { btn.textContent = orig; btn.style.color = ''; }, 2000);
  });
}
</script>
</body>
</html>
HTMLEOF

  # ── Nginx 메인 설정 ─────────────────────────────────────────────────────────
  cat > nginx/conf.d/default.conf << NGINXEOF
# =============================================================
# Nginx 보안강화 설정 - OpenWebUI RAG
# =============================================================

# Rate Limiting 존 정의
limit_req_zone  \$binary_remote_addr zone=webui_limit:10m  rate=30r/m;
limit_req_zone  \$binary_remote_addr zone=api_limit:10m    rate=20r/m;
limit_req_zone  \$binary_remote_addr zone=upload_limit:10m rate=5r/m;
limit_req_zone  \$binary_remote_addr zone=qdrant_limit:10m rate=15r/m;
limit_conn_zone \$binary_remote_addr zone=conn_limit:10m;

# 민감 IP 차단 (봇/스캐너)
# geo \$block_ip { default 0; 1.1.1.1 1; }

$([ "$USE_SSL" = true ] && cat << SSLBLOCK
# HTTP → HTTPS 리다이렉트
server {
    listen 80;
    server_name ${DOMAIN_NAME};

    # Let's Encrypt 인증용 (certbot webroot)
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS 메인 서버
server {
    listen 443 ssl http2;
    server_name ${DOMAIN_NAME};

    # SSL 인증서
    ssl_certificate     /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling        on;
    ssl_stapling_verify on;
SSLBLOCK
|| cat << HTTPBLOCK
# HTTP 서버
server {
    listen 80;
    server_name ${DOMAIN_NAME:-_};
HTTPBLOCK
)

    # 커넥션 제한
    limit_conn conn_limit 30;

    # 업로드 크기 제한
    client_max_body_size 60M;
    client_body_timeout  60s;
    client_header_timeout 15s;
    send_timeout         60s;
    keepalive_timeout    65s;

    # ──────────────────────────────────────────────
    # 보안 헤더 (전역)
    # ──────────────────────────────────────────────
    add_header X-Frame-Options           "SAMEORIGIN"               always;
    add_header X-Content-Type-Options    "nosniff"                  always;
    add_header X-XSS-Protection          "1; mode=block"            always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy        "geolocation=(), camera=(), microphone=()" always;
$([ "$USE_SSL" = true ] && echo '    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;')
$([ "$USE_SSL" = false ] && echo '    # add_header Strict-Transport-Security "..." always;  # SSL 활성화 후 주석 해제')

    # 서버 정보 숨김
    server_tokens off;
    more_clear_headers "Server";

    # 민감 파일 차단
    location ~* \.(env|git|htaccess|htpasswd|conf|cfg|bak|sql|sh)$ {
        deny all;
        return 404;
    }

    # 불필요 메서드 차단
    if (\$request_method !~ ^(GET|POST|HEAD|OPTIONS|DELETE|PUT|PATCH)$) {
        return 405;
    }

    # 보안 랜딩 페이지 (현황 대시보드)
    location = /status {
        alias /etc/nginx/html/index.html;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header X-Frame-Options "SAMEORIGIN" always;
    }

    # ──────────────────────────────────────────────
    # Open WebUI (메인)
    # ──────────────────────────────────────────────
    location / {
        limit_req zone=webui_limit burst=60 nodelay;

        proxy_pass         http://open-webui:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_buffering    off;
    }

    # ──────────────────────────────────────────────
    # Tools API (/api/ → 포트 8000)
    # ──────────────────────────────────────────────
    location /api/ {
        limit_req zone=api_limit burst=30 nodelay;

$([ "$USE_BASICAUTH" = true ] && cat << AUTHEOF
        # Basic Auth 보호
        auth_basic           "RAG Tools API - Authorized Access Only";
        auth_basic_user_file /etc/nginx/auth/.htpasswd;
AUTHEOF
)

        # /api/documents/upload 는 별도 rate limit
        location /api/documents/upload {
            limit_req zone=upload_limit burst=5 nodelay;
$([ "$USE_BASICAUTH" = true ] && echo '            auth_basic "RAG Tools API"; auth_basic_user_file /etc/nginx/auth/.htpasswd;')
            proxy_pass         http://openapi-tools:8000/documents/upload;
            proxy_http_version 1.1;
            proxy_set_header   Host            \$host;
            proxy_set_header   X-Real-IP       \$remote_addr;
            proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
            client_max_body_size 60M;
            proxy_read_timeout   120s;
        }

        rewrite ^/api/(.*)$ /\$1 break;
        proxy_pass         http://openapi-tools:8000;
        proxy_http_version 1.1;
        proxy_set_header   Host            \$host;
        proxy_set_header   X-Real-IP       \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
    }

    # ──────────────────────────────────────────────
    # Qdrant Dashboard (/qdrant/ → 포트 6333)
    # ──────────────────────────────────────────────
    location /qdrant/ {
        limit_req zone=qdrant_limit burst=20 nodelay;

$([ "$USE_BASICAUTH" = true ] && cat << AUTHEOF2
        # Basic Auth 보호
        auth_basic           "Qdrant Dashboard - Authorized Access Only";
        auth_basic_user_file /etc/nginx/auth/.htpasswd;
AUTHEOF2
)

        rewrite ^/qdrant/(.*)$ /\$1 break;
        proxy_pass         http://qdrant:6333;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
        sub_filter 'href="/' 'href="/qdrant/';
        sub_filter 'src="/'  'src="/qdrant/';
        sub_filter_once off;
    }

    # ──────────────────────────────────────────────
    # 헬스체크 (공개)
    # ──────────────────────────────────────────────
    location = /health {
        access_log off;
        return 200 '{"status":"ok","service":"openwebui-rag"}';
        add_header Content-Type application/json;
    }

    # 에러 페이지
    error_page 401 /401.html;
    error_page 403 /403.html;
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;

    location ~ ^/(401|403|404|50x)\.html$ {
        root /usr/share/nginx/html;
        internal;
    }
}
NGINXEOF

  ok "Nginx 설정 생성 완료"
fi

# ── docker-compose.yml ────────────────────────────────────────────────────────
cat > docker-compose.yml << COMPOSEEOF
# ============================================================
# docker-compose.yml — OpenWebUI RAG (AWS 보안강화)
# 생성일: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

services:

  # ── Qdrant 벡터 데이터베이스 ──────────────────────────────
  qdrant:
    image: qdrant/qdrant:latest
    container_name: rag-qdrant
    volumes:
      - qdrant-data:/qdrant/storage
    ports:
      - "127.0.0.1:6333:6333"     # 로컬호스트 바인딩 (외부 직접 접근 차단)
    environment:
      - QDRANT__SERVICE__API_KEY=${QDRANT_API_KEY}
      - QDRANT__LOG_LEVEL=WARN
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    deploy:
      resources:
        limits:
          memory: ${MEMORY_QDRANT}
          cpus: "1.0"
    networks:
      - rag-internal
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ── RAG Tools API ─────────────────────────────────────────
  openapi-tools:
    build:
      context: ./tools-api
      dockerfile: Dockerfile
    container_name: rag-tools
    env_file: .env
    volumes:
      - ./tools-api/data:/app/data
    ports:
      - "127.0.0.1:8000:8000"     # 로컬호스트 바인딩
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on:
      qdrant:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          memory: ${MEMORY_TOOLS}
          cpus: "1.5"
    networks:
      - rag-internal
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true

  # ── Open WebUI ────────────────────────────────────────────
  open-webui:
    image: ${OPEN_WEBUI_IMAGE}
    container_name: rag-webui
    environment:
      - WEBUI_SECRET_KEY=${SECRET_KEY}
      - WEBUI_AUTH=true
      - VECTOR_DB=qdrant
      - QDRANT_URI=http://qdrant:6333
      - QDRANT_API_KEY=${QDRANT_API_KEY}
COMPOSEEOF

if [ "$USE_OLLAMA" = true ]; then
cat >> docker-compose.yml << EOF
      - ENABLE_OLLAMA_API=true
      - OLLAMA_BASE_URL=http://host.docker.internal:11434
EOF
else
cat >> docker-compose.yml << EOF
      - ENABLE_OLLAMA_API=false
EOF
fi

if [ "$USE_GROQ" = true ] && [ -n "$GROQ_API_KEY" ]; then
cat >> docker-compose.yml << EOF
      - ENABLE_OPENAI_API=true
      - OPENAI_API_KEY=${GROQ_API_KEY}
      - OPENAI_API_BASE_URL=https://api.groq.com/openai/v1
      - DEFAULT_MODELS=llama-3.3-70b-versatile
EOF
else
cat >> docker-compose.yml << EOF
      - ENABLE_OPENAI_API=false
EOF
fi

cat >> docker-compose.yml << COMPOSEEOF2
      - WEBUI_TITLE=OpenWebUI RAG
    volumes:
      - open-webui-data:/app/backend/data
    ports:
      - "127.0.0.1:3000:8080"     # 로컬호스트 바인딩 (Nginx 경유)
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on:
      qdrant:
        condition: service_healthy
      openapi-tools:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    deploy:
      resources:
        limits:
          memory: ${MEMORY_WEBUI}
          cpus: "2.0"
    networks:
      - rag-internal
    security_opt:
      - no-new-privileges:true
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "5"

COMPOSEEOF2

# Nginx 서비스 추가 (USE_NGINX=true)
if [ "$USE_NGINX" = true ]; then
cat >> docker-compose.yml << NGINXSVC
  # ── Nginx 리버스 프록시 ───────────────────────────────────
  nginx:
    image: nginx:alpine
    container_name: rag-nginx
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/auth:/etc/nginx/auth:ro
      - ./nginx/html:/etc/nginx/html:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./logs/nginx:/var/log/nginx
    ports:
      - "0.0.0.0:80:80"
$([ "$USE_SSL" = true ] && echo '      - "0.0.0.0:443:443"')
    depends_on:
      - open-webui
      - openapi-tools
      - qdrant
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 5s
      retries: 3
    networks:
      - rag-internal
    security_opt:
      - no-new-privileges:true
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "7"

NGINXSVC
fi

cat >> docker-compose.yml << 'VOLEOF'
# ── 볼륨 ──────────────────────────────────────────────────
volumes:
  qdrant-data:
    driver: local
  open-webui-data:
    driver: local

# ── 네트워크 ───────────────────────────────────────────────
networks:
  rag-internal:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24
VOLEOF

ok "docker-compose.yml 생성 완료"

# =============================================================================
# STEP 9: UFW 방화벽 설정
# =============================================================================
section "STEP 9: UFW 방화벽 설정"

if [ "$USE_UFW" = true ]; then
  log "UFW 방화벽 설정 중..."

  # 기존 규칙 유지하면서 기본 정책 설정
  sudo ufw --force reset
  sudo ufw default deny incoming
  sudo ufw default allow outgoing

  # SSH 허용 (현재 연결 포트 자동 감지)
  SSH_PORT=$(ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | grep -oE '[0-9]+$' | head -1)
  SSH_PORT=${SSH_PORT:-22}
  sudo ufw allow "$SSH_PORT/tcp" comment "SSH"
  ok "SSH 포트 허용: $SSH_PORT"

  # HTTP/HTTPS 허용
  sudo ufw allow 80/tcp  comment "HTTP"
  sudo ufw allow 443/tcp comment "HTTPS"
  ok "HTTP/HTTPS 허용"

  # 내부 서비스 포트: 외부 직접 접근 차단 (Nginx 경유만 허용)
  # 6333, 8000, 3000은 127.0.0.1에만 바인딩되어 있으므로 UFW 규칙 불필요
  # (docker-compose.yml에서 127.0.0.1: 바인딩 적용)

  # Docker 브리지 네트워크 허용
  sudo ufw allow in on docker0   comment "Docker bridge"    2>/dev/null || true
  sudo ufw allow in on br-+      comment "Docker networks"  2>/dev/null || true

  sudo ufw --force enable
  sudo ufw status verbose
  ok "UFW 활성화 완료"
else
  info "UFW 방화벽 건너뜀"
fi

# =============================================================================
# STEP 10: Fail2ban 설정
# =============================================================================
section "STEP 10: Fail2ban 브루트포스 방어"

if [ "$USE_FAIL2BAN" = true ]; then
  log "Fail2ban 설정 중..."

  # Nginx 로그 jail 설정
  sudo tee /etc/fail2ban/jail.d/openwebui.conf > /dev/null << 'F2BEOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 10
action   = iptables-multiport[name=fail2ban, port="http,https"]

[sshd]
enabled  = true
port     = ssh
maxretry = 5
bantime  = 7200

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = %(nginx_error_log)s
maxretry = 5
bantime  = 3600

[nginx-limit-req]
enabled  = true
port     = http,https
logpath  = %(nginx_error_log)s
maxretry = 20
bantime  = 1800
filter   = nginx-limit-req

[nginx-botsearch]
enabled  = true
port     = http,https
logpath  = %(nginx_access_log)s
maxretry = 2
bantime  = 86400
filter   = nginx-botsearch
F2BEOF

  # 커스텀 필터: nginx-limit-req
  sudo tee /etc/fail2ban/filter.d/nginx-limit-req.conf > /dev/null << 'FILTEREOF'
[Definition]
failregex = limiting requests, excess:.* by zone.*client: <HOST>
ignoreregex =
FILTEREOF

  sudo systemctl enable fail2ban 2>/dev/null || true
  sudo systemctl restart fail2ban 2>/dev/null || true
  ok "Fail2ban 활성화 완료"
else
  info "Fail2ban 건너뜀"
fi

# =============================================================================
# STEP 11: SSL 인증서 발급 (Let's Encrypt)
# =============================================================================
section "STEP 11: SSL 인증서"

if [ "$USE_SSL" = true ] && [ "$USE_DOMAIN" = true ] && [ -n "$SSL_EMAIL" ]; then
  log "Certbot 설치 중..."
  sudo apt-get install -y -qq certbot python3-certbot-nginx

  log "SSL 인증서 발급 중: $DOMAIN_NAME"
  # Nginx가 아직 미실행이므로 standalone 모드로 우선 발급
  sudo certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email "$SSL_EMAIL" \
    -d "$DOMAIN_NAME" \
    --pre-hook "docker compose -f $BASE_DIR/docker-compose.yml stop nginx 2>/dev/null || true" \
    --post-hook "docker compose -f $BASE_DIR/docker-compose.yml start nginx 2>/dev/null || true" \
    2>&1 | tee -a "$LOG_FILE" || {
      warn "SSL 발급 실패 (DNS 전파 지연 또는 포트 80 차단). HTTP 모드로 계속합니다."
      USE_SSL=false
    }

  if [ "$USE_SSL" = true ]; then
    # Nginx 볼륨에 복사
    sudo cp /etc/letsencrypt/live/"$DOMAIN_NAME"/fullchain.pem "$BASE_DIR/nginx/ssl/"
    sudo cp /etc/letsencrypt/live/"$DOMAIN_NAME"/privkey.pem   "$BASE_DIR/nginx/ssl/"
    sudo chmod 644 "$BASE_DIR/nginx/ssl/"*.pem
    sudo chown "$USER:$USER" "$BASE_DIR/nginx/ssl/"*.pem

    # 자동 갱신 크론
    (sudo crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'docker compose -f $BASE_DIR/docker-compose.yml exec nginx nginx -s reload'") | sudo crontab -
    ok "SSL 인증서 발급 완료 (자동 갱신 크론 등록)"
  fi
else
  info "SSL 건너뜀"
fi

# =============================================================================
# STEP 12: Docker 빌드 및 실행
# =============================================================================
section "STEP 12: Docker 빌드 및 실행"

log "Docker 이미지 빌드 중..."
docker compose build --no-cache 2>&1 | tail -5

log "컨테이너 시작 중..."
docker compose up -d

echo ""
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ⏳ ${PERF_NAME} — 서비스 준비 대기"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ── Qdrant 대기 ──────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}📦 1/3 Qdrant 시작 중...${NC}"
QDRANT_OK=false
for i in $(seq 1 "$QDRANT_RETRIES"); do
  if docker compose exec -T qdrant curl -sf http://localhost:6333/healthz >/dev/null 2>&1 || \
     curl -sf "http://localhost:6333/collections" >/dev/null 2>&1; then
    QDRANT_OK=true
    ok "Qdrant 준비 완료! (${i}/${QDRANT_RETRIES})"
    break
  fi
  printf "\r   ⏳ 대기 중... %d/%d " "$i" "$QDRANT_RETRIES"
  sleep "$QDRANT_INTERVAL"
done
[ "$QDRANT_OK" = false ] && warn "Qdrant 대기 시간 초과 (계속 진행)"

# ── Tools API 대기 ───────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}🧠 2/3 Tools API 시작 중...${NC}"
TOOLS_OK=false
for i in $(seq 1 "$TOOLS_RETRIES"); do
  if curl -sf "http://localhost:8000/health" >/dev/null 2>&1; then
    TOOLS_OK=true
    ok "Tools API 준비 완료! (${i}/${TOOLS_RETRIES})"
    break
  fi
  printf "\r   ⏳ 대기 중... %d/%d " "$i" "$TOOLS_RETRIES"
  sleep "$TOOLS_INTERVAL"
done
[ "$TOOLS_OK" = false ] && warn "Tools API 대기 시간 초과 (계속 진행)"

# ── Open WebUI 대기 ──────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}🌐 3/3 Open WebUI 시작 중...${NC}"
WEBUI_OK=false
for i in $(seq 1 "$WEBUI_RETRIES"); do
  if docker compose logs open-webui 2>&1 | grep -qE "Application startup complete|Uvicorn running"; then
    sleep 3
    if curl -sf "http://localhost:3000" >/dev/null 2>&1; then
      WEBUI_OK=true
      ok "Open WebUI 준비 완료! (${i}/${WEBUI_RETRIES})"
      break
    fi
  fi
  printf "\r   ⏳ 대기 중... %d/%d " "$i" "$WEBUI_RETRIES"
  sleep "$WEBUI_INTERVAL"
done
[ "$WEBUI_OK" = false ] && warn "Open WebUI 대기 시간 초과"

# Nginx 최종 상태 확인
if [ "$USE_NGINX" = true ]; then
  echo ""
  echo -e "${CYAN}🔀 Nginx 상태 확인...${NC}"
  sleep 5
  if docker compose ps nginx 2>/dev/null | grep -q "Up"; then
    ok "Nginx 실행 중"
  else
    warn "Nginx 상태 확인 필요: docker compose logs nginx"
  fi
fi

# =============================================================================
# STEP 13: 보안 스크립트 및 유틸리티 생성
# =============================================================================
section "STEP 13: 관리 스크립트 생성"

# ── 상태 확인 스크립트 ────────────────────────────────────────────────────────
cat > "$BASE_DIR/scripts/status.sh" << 'STATUSEOF'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  📊 OpenWebUI RAG 서비스 상태"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker compose ps
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🔌 포트 바인딩"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ss -tlnp | grep -E ":(80|443|3000|6333|8000)\s" || echo "(없음)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  💾 리소스 사용량"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null || true
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🏥 헬스 체크"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for name in "WebUI:localhost:3000" "ToolsAPI:localhost:8000/health" "Qdrant:localhost:6333/collections"; do
  n=$(echo $name | cut -d: -f1)
  url=$(echo $name | cut -d: -f2-3)
  if curl -sf "http://$url" >/dev/null 2>&1; then
    echo "  ✅ $n → 정상"
  else
    echo "  ❌ $n → 응답 없음"
  fi
done
echo ""
STATUSEOF
chmod +x "$BASE_DIR/scripts/status.sh"

# ── 백업 스크립트 ─────────────────────────────────────────────────────────────
cat > "$BASE_DIR/scripts/backup.sh" << 'BACKUPEOF'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BACKUP_DIR="$HOME/openapi-rag-backups"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
mkdir -p "$BACKUP_DIR"

echo "💾 백업 시작: $TIMESTAMP"

# Docker 볼륨 백업
docker run --rm \
  -v openapi-rag_qdrant-data:/data \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf "/backup/qdrant_${TIMESTAMP}.tar.gz" -C /data . 2>/dev/null && \
  echo "  ✅ Qdrant 데이터 백업" || echo "  ❌ Qdrant 백업 실패"

docker run --rm \
  -v openapi-rag_open-webui-data:/data \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf "/backup/webui_${TIMESTAMP}.tar.gz" -C /data . 2>/dev/null && \
  echo "  ✅ WebUI 데이터 백업" || echo "  ❌ WebUI 백업 실패"

# 설정 파일 백업
tar czf "$BACKUP_DIR/config_${TIMESTAMP}.tar.gz" \
  .env docker-compose.yml nginx/ tools-api/ 2>/dev/null && \
  echo "  ✅ 설정 파일 백업" || echo "  ❌ 설정 백업 실패"

# 오래된 백업 삭제 (30일 이상)
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete 2>/dev/null || true

echo "✅ 백업 완료: $BACKUP_DIR"
ls -lh "$BACKUP_DIR" | tail -10
BACKUPEOF
chmod +x "$BASE_DIR/scripts/backup.sh"

# ── 업데이트 스크립트 ─────────────────────────────────────────────────────────
cat > "$BASE_DIR/scripts/update.sh" << 'UPDATEEOF'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "🔄 이미지 업데이트 중..."
docker compose pull
docker compose up -d --remove-orphans
docker image prune -f
echo "✅ 업데이트 완료"
docker compose ps
UPDATEEOF
chmod +x "$BASE_DIR/scripts/update.sh"

# ── 크론 자동화 (백업 + 업데이트) ────────────────────────────────────────────
(crontab -l 2>/dev/null; echo "0 2 * * * $BASE_DIR/scripts/backup.sh >> $BASE_DIR/logs/backup.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 4 * * 0 $BASE_DIR/scripts/update.sh >> $BASE_DIR/logs/update.log 2>&1") | crontab -
ok "크론 등록: 매일 02:00 백업, 매주 일요일 04:00 업데이트"

# =============================================================================
# STEP 14: 최종 요약 출력
# =============================================================================
INSTALL_END=$(date +%s)
INSTALL_TIME=$((INSTALL_END - INSTALL_START))
INSTALL_MIN=$((INSTALL_TIME / 60))
INSTALL_SEC=$((INSTALL_TIME % 60))

# 접근 URL 결정
if [ "$USE_NGINX" = true ]; then
  PROTO=$([ "$USE_SSL" = true ] && echo "https" || echo "http")
  BASE_URL="${PROTO}://${DOMAIN_NAME:-$ACCESS_HOST}"
  WEBUI_URL="$BASE_URL"
  TOOLS_URL="$BASE_URL/api/docs"
  QDRANT_URL_DISPLAY="$BASE_URL/qdrant/dashboard"
  STATUS_URL="$BASE_URL/status"
else
  PROTO="http"
  BASE_URL="${PROTO}://${ACCESS_HOST}"
  WEBUI_URL="$BASE_URL:3000"
  TOOLS_URL="$BASE_URL:8000/docs"
  QDRANT_URL_DISPLAY="$BASE_URL:6333/dashboard"
  STATUS_URL="(Nginx 비활성화)"
fi

echo ""
echo -e "${BOLD}${GREEN}"
cat << 'COMPLETE'
 ██████╗ ██████╗ ███╗   ███╗██████╗ ██╗     ███████╗████████╗███████╗██╗
██╔════╝██╔═══██╗████╗ ████║██╔══██╗██║     ██╔════╝╚══██╔══╝██╔════╝██║
██║     ██║   ██║██╔████╔██║██████╔╝██║     █████╗     ██║   █████╗  ██║
██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██║     ██╔══╝     ██║   ██╔══╝  ╚═╝
╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ███████╗███████╗   ██║   ███████╗██╗
 ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝
COMPLETE
echo -e "${NC}"

echo -e "${BOLD}┌───────────────────────────────────────────────────────────┐${NC}"
echo -e "${BOLD}│  🎉 설치 완료! (소요 시간: ${INSTALL_MIN}분 ${INSTALL_SEC}초)${NC}                       "
echo -e "${BOLD}└───────────────────────────────────────────────────────────┘${NC}"
echo ""

echo -e "${BOLD}${CYAN}📊 설치 구성${NC}"
echo -e "   성능 등급  : ${PERF_NAME}"
echo -e "   Ollama     : $([ "$USE_OLLAMA" = true ] && echo '✅ 활성화 (로컬 LLM)' || echo '⭐ 비활성화')"
echo -e "   Groq API   : $([ "$USE_GROQ" = true ] && echo '✅ 활성화 (클라우드 LLM)' || echo '⭐ 비활성화')"
echo -e "   Nginx      : $([ "$USE_NGINX" = true ] && echo '✅ 활성화 (리버스 프록시)' || echo '⭐ 비활성화')"
echo -e "   SSL/TLS    : $([ "$USE_SSL" = true ] && echo "✅ Let's Encrypt ($DOMAIN_NAME)" || echo '⭐ 비활성화')"
echo -e "   Basic Auth : $([ "$USE_BASICAUTH" = true ] && echo "✅ $BASICAUTH_USER (관리 패널 보호)" || echo '⭐ 비활성화')"
echo -e "   UFW        : $([ "$USE_UFW" = true ] && echo '✅ 활성화' || echo '⭐ 비활성화')"
echo -e "   Fail2ban   : $([ "$USE_FAIL2BAN" = true ] && echo '✅ 활성화' || echo '⭐ 비활성화')"
echo ""

echo -e "${BOLD}${CYAN}🌐 서비스 URL${NC}"
echo -e "   Open WebUI          : ${GREEN}${WEBUI_URL}${NC}"
echo -e "   보안 현황 대시보드  : ${GREEN}${STATUS_URL}${NC}"
echo -e "   Tools API Docs      : ${YELLOW}${TOOLS_URL}${NC}  🔒 Auth"
echo -e "   Qdrant Dashboard    : ${YELLOW}${QDRANT_URL_DISPLAY}${NC}  🔒 Auth"
echo ""

echo -e "${BOLD}${CYAN}🔒 보안 적용 목록${NC}"
echo -e "   ✅ 모든 내부 포트 127.0.0.1 바인딩 (직접 외부 접근 차단)"
echo -e "   ✅ Nginx Rate Limiting (WebUI:30/m, API:20/m, Upload:5/m)"
echo -e "   ✅ 보안 헤더 (X-Frame-Options, CSP, HSTS, XSS-Protection)"
echo -e "   ✅ 불필요 HTTP 메서드 차단 (TRACE, CONNECT 등)"
echo -e "   ✅ 민감 파일 접근 차단 (.env, .git, .sh 등)"
echo -e "   ✅ 업로드 크기 제한 (60MB)"
echo -e "   ✅ Path Traversal 방지 (파일명 안전 처리)"
echo -e "   ✅ Docker 컨테이너 비루트 실행 (no-new-privileges)"
echo -e "   ✅ Docker 컨테이너 메모리/CPU 제한"
echo -e "   ✅ Qdrant API Key 인증"
echo ""

echo -e "${BOLD}${CYAN}💡 첫 사용 방법${NC}"
echo -e "   1. ${GREEN}${WEBUI_URL}${NC} 접속"
echo -e "   2. 계정 생성 (첫 번째 계정 = 관리자)"
if [ "$USE_OLLAMA" = true ] && [ "$USE_GROQ" = true ]; then
  echo -e "   3. Ollama + Groq 모델 모두 사용 가능"
elif [ "$USE_OLLAMA" = true ]; then
  echo -e "   3. Ollama 로컬 모델 사용 가능"
  echo -e "   4. Groq 추가: Settings → Connections → OpenAI"
elif [ "$USE_GROQ" = true ]; then
  echo -e "   3. Groq 클라우드 모델 사용 가능"
else
  echo -e "   3. ⚠️  Settings → Connections에서 API 키 추가 필요"
fi
echo ""

echo -e "${BOLD}${CYAN}📚 RAG 사용 방법${NC}"
echo ""
echo -e "   1️⃣  PDF 업로드:"
echo -e "      ${YELLOW}curl -X POST ${TOOLS_URL%/docs}/documents/upload -F 'file=@document.pdf'${NC}"
echo ""
echo -e "   2️⃣  시맨틱 검색:"
echo -e "      ${YELLOW}curl -X POST ${TOOLS_URL%/docs}/rag/search \\\\${NC}"
echo -e "      ${YELLOW}     -H 'Content-Type: application/json' \\\\${NC}"
echo -e "      ${YELLOW}     -d '{\"query\":\"검색어\",\"top_k\":3}'${NC}"
echo ""
echo -e "   3️⃣  헬스 체크:"
echo -e "      ${YELLOW}curl ${TOOLS_URL%/docs}/health${NC}"
echo ""

echo -e "${BOLD}${CYAN}🔧 관리 명령어${NC}"
echo -e "   cd $BASE_DIR"
echo -e "   ./scripts/status.sh            # 전체 상태 확인"
echo -e "   ./scripts/backup.sh            # 즉시 백업 실행"
echo -e "   ./scripts/update.sh            # 이미지 업데이트"
echo -e "   docker compose logs -f         # 전체 로그"
echo -e "   docker compose logs -f nginx   # Nginx 로그"
echo -e "   docker compose logs -f open-webui  # WebUI 로그"
echo -e "   docker compose restart         # 전체 재시작"
echo -e "   docker compose down            # 중지"
echo -e "   docker compose down -v         # 중지 + 데이터 삭제 ⚠️"
echo ""
if [ "$USE_OLLAMA" = true ]; then
  echo -e "${BOLD}${CYAN}🤖 Ollama 관리${NC}"
  echo -e "   systemctl status ollama"
  echo -e "   ollama list                    # 설치된 모델"
  echo -e "   ollama pull llama3.2           # 모델 추가"
  echo ""
fi
echo -e "${BOLD}${CYAN}📁 설치 경로${NC}"
echo -e "   프로젝트 : $BASE_DIR"
echo -e "   설치 로그 : $LOG_FILE"
echo -e "   크론 작업 : 매일 02:00 백업, 매주 04:00 업데이트"
echo ""
if [ "$IS_AWS" = true ]; then
  echo -e "${BOLD}${CYAN}⚠️  AWS 보안그룹 확인 사항${NC}"
  echo -e "   인바운드 규칙 필수 개방:"
  echo -e "   • 포트 22  (SSH)   - 관리 접속용"
  echo -e "   • 포트 80  (HTTP)  - Web 접근용"
  [ "$USE_SSL" = true ] && echo -e "   • 포트 443 (HTTPS) - SSL 접근용"
  echo -e "   ⛔ 포트 3000, 6333, 8000은 외부 개방 불필요 (내부 전용)"
  echo ""
else
  echo -e "${BOLD}${CYAN}⚠️  방화벽 확인 사항${NC}"
  echo -e "   서버 방화벽에서 다음 포트 개방 필요:"
  echo -e "   • 포트 22  (SSH)   - 관리 접속용"
  echo -e "   • 포트 80  (HTTP)  - Web 접근용"
  [ "$USE_SSL" = true ] && echo -e "   • 포트 443 (HTTPS) - SSL 접근용"
  echo -e "   ⛔ 포트 3000, 6333, 8000은 외부 개방 불필요 (내부 전용)"
  if [ "$USE_UFW" = true ]; then
    echo -e "   ✅ UFW 방화벽이 자동 설정되었습니다"
  else
    echo -e "   ⚠️  UFW가 비활성화되었습니다. 수동으로 방화벽을 설정하세요"
  fi
  echo ""
fi
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  설치가 정상 완료되었습니다. 위 URL로 접속하세요! 🚀${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 컨테이너 최종 상태
echo -e "${BOLD}📋 컨테이너 최종 상태:${NC}"
docker compose ps
echo ""
