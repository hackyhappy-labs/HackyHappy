# 🔐 OpenWebUI RAG 보안강화 설치 가이드

> **Docker + Ollama + Groq + Qdrant + Nginx + SSL + UFW + Fail2ban**  
> 아무것도 없는 Ubuntu 서버에서 원터치로 RAG 시스템을 구축하는 가이드입니다.

---

## 📋 목차

1. [지원 환경](#1-지원-환경)
2. [서버 사양 확인](#2-서버-사양-확인)
3. [Ubuntu 설치 후 첫 번째 할 일](#3-ubuntu-설치-후-첫-번째-할-일)
4. [사전 필수 패키지 설치](#4-사전-필수-패키지-설치)
5. [Docker 설치](#5-docker-설치)
6. [네트워크 및 방화벽 설정](#6-네트워크-및-방화벽-설정)
7. [Groq API 키 발급 (선택)](#7-groq-api-키-발급-선택)
8. [설치 스크립트 실행](#8-설치-스크립트-실행)
9. [설치 후 확인](#9-설치-후-확인)
10. [오류 해결](#10-오류-해결)

---

## 1. 지원 환경

| 항목 | 지원 범위 |
|------|-----------|
| **OS** | Ubuntu 20.04 / 22.04 / 24.04 LTS |
| **아키텍처** | x86_64 (AMD64) |
| **환경** | AWS EC2, Google Cloud, Azure, DigitalOcean, 온프레미스 |

> ⚠️ **CentOS, RHEL, Amazon Linux, Alpine 등은 지원하지 않습니다.**  
> 반드시 Ubuntu (Debian 계열) 를 사용하세요.

---

## 2. 서버 사양 확인

설치 스크립트가 사양을 자동 감지하여 성능 등급을 결정합니다.

| 등급 | CPU | RAM | 디스크 | 비고 |
|------|-----|-----|--------|------|
| 최소 | 1코어 | 2GB | 20GB | 테스트용 |
| 중급 | 2코어 | 4GB | 30GB | 소규모 팀 |
| **권장** | **4코어** | **8GB** | **50GB** | **일반 서비스** |
| 고성능 | 6코어+ | 16GB+ | 100GB+ | Ollama 로컬 LLM |

> 💡 Groq Cloud API만 사용할 경우 4GB RAM으로 충분합니다.  
> 💡 Ollama 로컬 LLM(llama3.2 등)을 사용하려면 최소 8GB RAM이 필요합니다.

---

## 3. Ubuntu 설치 후 첫 번째 할 일

### ⚠️ 중요: root 계정으로 설치 스크립트를 실행하면 안 됩니다

설치 스크립트는 **sudo 권한이 있는 일반 사용자 계정**으로 실행해야 합니다.

### 3-1. OS 버전 확인

```bash
# OS 버전 확인
lsb_release -a

# 아키텍처 확인 (x86_64 여야 함)
uname -m
```

### 3-2. 일반 사용자 계정 생성 (root로 로그인한 경우)

```bash
# 새 사용자 생성 (예: deploy)
adduser deploy

# sudo 권한 부여
usermod -aG sudo deploy

# 해당 계정으로 전환
su - deploy

# sudo 동작 확인 (root 출력되면 정상)
sudo whoami
```

> 💡 **AWS EC2 Ubuntu**는 기본 계정 `ubuntu`에 이미 sudo 권한이 있습니다.  
> 별도 계정 생성 없이 `ubuntu` 계정으로 바로 진행하세요.

### 3-3. SSH 접속 방법

```bash
# AWS EC2 (PEM 키 사용)
chmod 400 my-key.pem
ssh -i my-key.pem ubuntu@서버공인IP

# 일반 서버 (비밀번호)
ssh 사용자명@서버IP
```

---

## 4. 사전 필수 패키지 설치

> 🚀 **아래 명령을 순서대로 실행하세요.**  
> 완전히 새 Ubuntu 서버라면 `curl` 조차 없을 수 있으므로 반드시 진행해야 합니다.

### 4-1. 시스템 패키지 업데이트

```bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get autoremove -y
```

> ⚠️ 업데이트 중 커널 업그레이드가 있다면 재부팅이 필요할 수 있습니다.
> ```bash
> sudo reboot
> # 재부팅 후 SSH 재접속
> ```

### 4-2. 핵심 도구 설치

```bash
sudo apt-get install -y \
  curl \
  wget \
  git \
  openssl \
  ca-certificates \
  gnupg \
  lsb-release \
  apt-transport-https \
  software-properties-common \
  python3 \
  python3-pip
```

> 💡 **Python 3 설치 이유**  
> Tools API(FastAPI)는 Docker 컨테이너 안에서 실행되므로 호스트의 Python 버전과 무관합니다.  
> 단, **SSL 인증서 발급 시** `certbot python3-certbot-nginx` 패키지가 필요하므로 미리 설치합니다.  
> Ubuntu 최소 설치(minimal) 이미지 환경에서는 python3가 없을 수 있습니다.

```bash
# 설치된 Python 버전 확인
python3 --version
# 출력 예: Python 3.10.12  (3.8 이상이면 정상)
```

### 4-3. 유틸리티 설치 (권장)

```bash
sudo apt-get install -y \
  htop \
  net-tools \
  unzip \
  jq \
  screen
```

### 4-4. 설치 확인

```bash
curl --version | head -1
wget --version | head -1
git --version
python3 --version
```

---

## 5. Docker 설치

> ⚠️ **Docker 설치 후 반드시 재접속해야 합니다.**  
> 재접속 없이 스크립트를 실행하면 Docker 권한 오류가 발생합니다.

### 5-1. Docker 설치

```bash
# Docker 공식 원터치 설치
curl -fsSL https://get.docker.com | sudo sh

# 현재 사용자를 docker 그룹에 추가
sudo usermod -aG docker $USER

# ★ 그룹 적용을 위해 로그아웃
exit
```

### 5-2. SSH 재접속 후 동작 확인

```bash
# sudo 없이 docker 명령 확인
docker ps

# Docker Compose v2 확인 (반드시 'docker compose' 형식이어야 함)
docker compose version

# 정상 동작 테스트
docker run --rm hello-world
```

> ✅ `docker ps` 와 `docker compose version` 이 오류 없이 실행되면 준비 완료입니다.

### 5-3. Docker 자동 시작 설정

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

---

## 6. 네트워크 및 방화벽 설정

### 6-1. 열어야 할 포트

| 포트 | 용도 | 외부 개방 |
|------|------|-----------|
| **22** | SSH 관리 접속 | ✅ 필수 (본인 IP만 권장) |
| **80** | HTTP 웹 접근 | ✅ 필수 |
| **443** | HTTPS (SSL 사용 시) | ✅ SSL 사용 시 |
| 3000 | Open WebUI | ❌ Nginx 사용 시 불필요 |
| 6333 | Qdrant DB | ❌ 내부 전용 |
| 8000 | Tools API | ❌ 내부 전용 |
| 11434 | Ollama | ❌ 내부 전용 |

> 🔒 3000, 6333, 8000, 11434 포트는 `127.0.0.1`에만 바인딩되어 외부 직접 접근이 차단됩니다.

### 6-2. AWS EC2 보안그룹 설정

```
AWS 콘솔 → EC2 → 인스턴스 선택
→ [보안] 탭 → 보안 그룹 클릭
→ [인바운드 규칙 편집]
→ 규칙 추가: SSH(22), HTTP(80), HTTPS(443)
→ [규칙 저장]
```

### 6-3. 인터넷 연결 확인

```bash
# 외부 연결 확인
ping -c 3 google.com

# Docker Hub 접근 확인
curl -sf https://hub.docker.com > /dev/null && echo "✅ Docker Hub OK"

# GitHub Container Registry 확인
curl -sf https://ghcr.io > /dev/null && echo "✅ GitHub Registry OK"
```

### 6-4. 도메인 DNS 설정 (SSL 사용 시)

SSL 인증서를 발급받으려면 도메인이 서버 IP를 가리켜야 합니다.  
DNS 레코드 전파에 최대 48시간이 걸릴 수 있으므로 미리 설정하세요.

| 레코드 | 호스트 | 값 |
|--------|--------|----|
| A | example.com | 서버 공인 IP |
| A | www.example.com | 서버 공인 IP |

```bash
# DNS 전파 확인 (서버 IP와 일치해야 함)
nslookup example.com
```

---

## 7. Groq API 키 발급 (선택)

Ollama 없이도 **Groq 무료 Cloud API**로 고성능 LLM을 사용할 수 있습니다.  
설치 중에 입력이 필요하므로 미리 발급해 두세요.

1. [https://console.groq.com](https://console.groq.com) 접속
2. 회원가입 / 로그인 (Google, GitHub 소셜 로그인 가능)
3. **API Keys** → **Create API Key** 클릭
4. 키 이름 입력 후 생성 → 복사하여 보관

```
발급된 키 형식: gsk_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

```bash
# 발급한 키 동작 테스트 (선택)
curl -s https://api.groq.com/openai/v1/models \
  -H "Authorization: Bearer gsk_YOUR_API_KEY" | jq '.data[].id'
```

> 💡 **제공 모델:** llama-3.3-70b-versatile, llama-3.1-8b-instant, mixtral-8x7b-32768 등  
> 스크립트 기본 모델은 **llama-3.3-70b-versatile** 로 설정됩니다.

---

## 8. 설치 스크립트 실행

### 8-1. 설치 전 최종 체크리스트

```
□ Ubuntu 20.04 / 22.04 / 24.04 LTS 확인
□ root가 아닌 sudo 권한 일반 계정으로 접속
□ sudo whoami → root 출력 확인
□ apt-get update 완료
□ curl, wget, git 설치 확인
□ python3 --version 확인 (3.8 이상)
□ docker ps 오류 없이 실행 (재접속 완료)
□ docker compose version 확인
□ 포트 22, 80 개방 확인
□ (SSL 사용 시) 도메인 DNS A레코드 설정 완료
□ (선택) Groq API Key 준비
```

### 8-2. 스크립트 다운로드 및 실행

```bash
# 스크립트 다운로드
wget -O install.sh https://raw.githubusercontent.com/YOUR_GITHUB_ID/YOUR_REPO/main/install_openwebui_rag_aws.sh

# 실행 권한 부여
chmod +x install.sh

# 실행
./install.sh
```

### 8-3. screen 세션에서 실행 (SSH 끊김 방지 — 강력 권장)

```bash
# screen 세션 시작
screen -S rag-install

# 세션 안에서 스크립트 실행
./install.sh

# SSH가 끊겼을 때 재연결
screen -r rag-install
```

### 8-4. 설치 중 입력 항목

스크립트 실행 중 아래 값들을 입력하라는 메시지가 나옵니다.

| 항목 | 설명 | 기본값 |
|------|------|--------|
| 도메인 | 사용할 도메인 (없으면 Enter) | IP 직접 접근 |
| Nginx | 리버스 프록시 사용 여부 | Y |
| SSL | Let's Encrypt 자동 발급 | Y (도메인 있을 때) |
| SSL 이메일 | 인증서 발급용 이메일 | - |
| Basic Auth ID | 관리 패널 접근 계정 | admin |
| Basic Auth 비밀번호 | 8자 이상 | - |
| Ollama | 로컬 LLM 설치 여부 | 사양에 따라 다름 |
| Groq API Key | 발급한 키 입력 | 건너뜀 |
| Fail2ban | 브루트포스 방어 | Y |
| UFW | 방화벽 활성화 | Y |

---

## 9. 설치 후 확인

### 접속 URL

| 서비스 | URL | 비고 |
|--------|-----|------|
| Open WebUI | `http://서버IP` 또는 `https://도메인` | 메인 서비스 |
| Tools API Docs | `/api/docs` | 🔒 Basic Auth |
| Qdrant Dashboard | `/qdrant/dashboard` | 🔒 Basic Auth |
| 상태 페이지 | `/status` | 서비스 현황 |

### 서비스 상태 확인

```bash
cd ~/openapi-rag

# 전체 상태
./scripts/status.sh

# 컨테이너 목록
docker compose ps

# 로그 확인
docker compose logs -f
```

### 첫 로그인

1. 브라우저에서 WebUI 주소 접속
2. **계정 생성** (첫 번째 생성 계정 = 관리자)
3. Settings → Connections 에서 모델 연결 확인

---

## 10. 오류 해결

### ❌ "root로 실행하지 마세요" 오류

```bash
# 일반 사용자로 전환
su - ubuntu

# 또는 새 사용자 생성
adduser myuser && usermod -aG sudo myuser && su - myuser
```

### ❌ "docker: permission denied" 오류

```bash
# docker 그룹 추가 후 재접속
sudo usermod -aG docker $USER
exit
# SSH 재접속 후 테스트
docker ps
```

### ❌ "docker compose version" 오류 (구버전)

```bash
# 구버전 제거
sudo apt-get remove docker-compose

# Docker 최신 버전 재설치 (Compose v2 포함)
curl -fsSL https://get.docker.com | sudo sh

# 확인
docker compose version
```

### ❌ SSL 발급 실패

```bash
# DNS 전파 확인
dig +short your-domain.com

# 전파 안 됐다면 HTTP로 설치 후 나중에 발급
sudo certbot --nginx -d your-domain.com
```

### ❌ certbot 설치 실패 (python3 없음)

```bash
# python3 먼저 설치
sudo apt-get install -y python3 python3-pip

# certbot 재설치
sudo apt-get install -y certbot python3-certbot-nginx
```

### ❌ 포트 이미 사용 중 (port already in use)

```bash
# 포트 점유 확인
sudo ss -tlnp | grep -E ":80|:443"

# Apache 중지
sudo systemctl stop apache2 && sudo systemctl disable apache2

# 기존 Nginx 중지 (호스트 Nginx는 불필요)
sudo systemctl stop nginx && sudo systemctl disable nginx
```

### ❌ 디스크 공간 부족

```bash
# 사용량 확인
df -h

# Docker 이미지 정리
docker system prune -af

# 로그 정리
sudo journalctl --vacuum-size=100M
sudo apt-get clean && sudo apt-get autoremove -y
```

### 📄 로그 확인

```bash
# 설치 로그
cat ~/openwebui-install.log

# 컨테이너별 로그
cd ~/openapi-rag
docker compose logs -f open-webui
docker compose logs -f qdrant
docker compose logs -f nginx
docker compose logs -f openapi-tools
```

---

## 🔧 설치 후 관리 명령어

```bash
cd ~/openapi-rag

./scripts/status.sh          # 전체 상태 확인
./scripts/backup.sh          # 즉시 백업
./scripts/update.sh          # 이미지 업데이트

docker compose restart       # 전체 재시작
docker compose down          # 서비스 중지
docker compose down -v       # 중지 + 데이터 삭제 ⚠️
```

---

## 📦 설치되는 구성 요소

```
~/openapi-rag/
├── .env                    # 환경 설정 (API 키, 시크릿 등)
├── docker-compose.yml      # Docker 서비스 정의
├── tools-api/              # RAG Tools API (FastAPI)
│   ├── main.py
│   ├── requirements.txt
│   └── Dockerfile
├── nginx/                  # Nginx 리버스 프록시 설정
│   ├── conf.d/
│   ├── ssl/
│   └── auth/
├── scripts/                # 관리 스크립트
│   ├── status.sh
│   ├── backup.sh
│   └── update.sh
└── logs/                   # 로그 파일
```

---

## 📋 전체 사전 준비 요약 (원커맨드)

아래를 **순서대로** 실행하면 사전 준비가 완료됩니다.

```bash
# 1. 패키지 업데이트
sudo apt-get update && sudo apt-get upgrade -y

# 2. 필수 도구 설치
sudo apt-get install -y \
  curl wget git openssl ca-certificates gnupg \
  lsb-release apt-transport-https software-properties-common \
  python3 python3-pip \
  htop net-tools unzip jq screen

# 3. Docker 설치
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER

# 4. ★ 재접속 (반드시 필요)
exit
# → SSH 재접속 후 아래 진행

# 5. Docker 검증
docker ps
docker compose version

# 6. 스크립트 다운로드 및 실행
screen -S rag-install
wget -O install.sh https://raw.githubusercontent.com/YOUR_GITHUB_ID/YOUR_REPO/main/install_openwebui_rag_aws.sh
chmod +x install.sh && ./install.sh
```

---

## 📄 라이센스

MIT License
