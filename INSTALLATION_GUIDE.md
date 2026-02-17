# OpenWebUI RAG 설치 가이드

## 📋 설치 전 준비사항

### 1. 서버 준비
- **OS**: Ubuntu 20.04 / 22.04 / 24.04 LTS
- **최소 사양**: 2코어 4GB RAM 10GB 디스크
- **권장 사양**: 4코어 8GB RAM 50GB 디스크
- **네트워크**: 공인 IP 또는 도메인 (선택)

### 2. 필수 준비물

#### ✅ 서버 접속 정보
```bash
# SSH 접근 권한
ssh your-user@your-server-ip

# sudo 권한 확인
sudo -v
```

#### ⭐ 선택 준비물

| 항목 | 필수 여부 | 준비 방법 |
|------|----------|----------|
| **도메인** | 선택 | 도메인 구입 후 A 레코드를 서버 IP로 설정 |
| **Groq API Key** | 권장 | https://console.groq.com 무료 가입 후 발급 |
| **이메일** | SSL 사용 시 | Let's Encrypt 인증서 발급용 |

### 3. AWS EC2 사용 시 추가 설정

#### 보안 그룹 (Security Group) 인바운드 규칙

| 포트 | 프로토콜 | 소스 | 용도 |
|------|---------|------|------|
| 22 | TCP | 내 IP 또는 0.0.0.0/0 | SSH 관리 |
| 80 | TCP | 0.0.0.0/0 | HTTP (WebUI) |
| 443 | TCP | 0.0.0.0/0 | HTTPS (SSL 사용 시) |

**중요**: 3000, 6333, 8000 포트는 개방하지 마세요 (내부 전용)

---

## 🚀 설치 실행

### 방법 1: 다운로드 후 실행 (권장)

```bash
# 1. 스크립트 다운로드
wget https://your-s3-url/install_openwebui_rag_aws.sh

# 2. 실행 권한 부여
chmod +x install_openwebui_rag_aws.sh

# 3. 스크립트 실행
./install_openwebui_rag_aws.sh
```

### 방법 2: 원터치 실행

```bash
curl -fsSL https://your-s3-url/install_openwebui_rag_aws.sh | bash
```

---

## ⌨️ 설치 중 입력 사항

스크립트가 실행되면 다음 항목들을 순서대로 물어봅니다:

### 1. 도메인 설정 (60초 타임아웃)
```
🌐 도메인 입력 (Enter=IP 접근):
```
- **있으면**: `example.com` 입력
- **없으면**: Enter (IP로 접근)

### 2. Nginx 리버스 프록시 (30초 타임아웃)
```
🔀 Nginx 설치? (Enter=Y):
```
- **권장**: Y (엔터) - 보안 헤더, Rate Limiting 적용
- **비권장**: N - 직접 포트 접근

### 3. SSL 인증서 (도메인 있을 때만)
```
🔒 SSL 자동 발급? (Enter=Y):
📧 SSL 인증서 이메일:
```
- **도메인 있으면**: Y → 이메일 입력
- **없으면**: 자동 스킵

### 4. Basic Auth 설정 (30초 타임아웃)
```
🔑 Basic Auth 설정? (Enter=Y):
   관리자 ID (Enter=admin):
   관리자 비밀번호 (최소 8자):
```
- **권장**: Y → 관리자 계정 설정
- Tools API와 Qdrant 대시보드 보호용

### 5. Ollama 설치 (30초 타임아웃)
```
🤖 Ollama 설치/사용? (권장 여부는 서버 사양에 따라 표시):
```
- **고성능 서버**: Y 권장 (로컬 임베딩)
- **저사양 서버**: N 권장 (Groq API 사용)

### 6. Groq API Key (90초 타임아웃)
```
🔑 Groq API Key (Enter=건너뜀):
```
- **Ollama 없으면**: 반드시 입력 (없으면 모델 사용 불가)
- **Ollama 있으면**: 선택 (클라우드 모델 추가용)

### 7. Fail2ban (20초 타임아웃)
```
🛡️  Fail2ban 설치? (Enter=Y):
```
- **권장**: Y (브루트포스 공격 방어)

### 8. UFW 방화벽 (20초 타임아웃)
```
🔥 UFW 방화벽 활성화? (Enter=Y):
```
- **권장**: Y (자동 포트 관리)
- **주의**: SSH 포트 자동 감지 후 허용

### 9. 최종 확인 (20초 타임아웃)
```
▶ 위 설정으로 설치를 시작합니까? (Enter=Y):
```
- 설정 요약 확인 후 Enter

---

## ⏱️ 설치 소요 시간

| 서버 사양 | 예상 시간 |
|----------|----------|
| 고성능 (6코어 16GB↑) | 5~8분 |
| 중상급 (4코어 8GB) | 8~12분 |
| 중급 (2코어 4GB) | 12~18분 |
| 저사양 (2코어 2GB) | 18~30분 |

**실제 소요 시간은 네트워크 속도에 따라 달라집니다.**

---

## ✅ 설치 완료 후 해야 할 일

### 1. 접속 URL 확인

설치 완료 메시지에서 다음 정보 확인:

```
🌐 서비스 URL
   Open WebUI          : https://your-domain.com
   보안 현황 대시보드  : https://your-domain.com/status
   Tools API Docs      : https://your-domain.com/api/docs
   Qdrant Dashboard    : https://your-domain.com/qdrant/dashboard
```

### 2. 첫 계정 생성 (필수)

```bash
# 1. Open WebUI 접속
https://your-domain.com

# 2. 회원가입 클릭
# 3. 이메일, 비밀번호 입력
# 주의: 첫 번째 가입자가 자동으로 관리자 권한 획득
```

### 3. 모델 확인

```
Settings → Models
```
- **Ollama 설치 시**: 로컬 모델 표시됨
- **Groq API 입력 시**: 클라우드 모델 표시됨 (llama-3.3-70b-versatile 등)

### 4. RAG 테스트 (선택)

#### 방법 1: curl로 테스트
```bash
# PDF 업로드
curl -X POST https://your-domain.com/api/documents/upload \
  -u admin:your-password \
  -F "file=@test.pdf"

# 검색 테스트
curl -X POST https://your-domain.com/api/rag/search \
  -u admin:your-password \
  -H "Content-Type: application/json" \
  -d '{"query":"테스트 검색어","top_k":3}'
```

#### 방법 2: Open WebUI에서 테스트
```
1. 채팅 입력창에 문서 업로드 아이콘 클릭
2. PDF 파일 선택 후 업로드
3. "이 문서에서 [질문] 찾아줘" 입력
```

---

## 🔧 설치 후 관리

### 서비스 상태 확인
```bash
cd ~/openapi-rag
./scripts/status.sh
```

### 로그 확인
```bash
# 전체 로그
docker compose logs -f

# WebUI만
docker compose logs -f open-webui

# Nginx만
docker compose logs -f nginx
```

### 백업
```bash
# 즉시 백업
cd ~/openapi-rag
./scripts/backup.sh

# 백업 파일 위치
ls -lh ~/openapi-rag-backups/
```

### 업데이트
```bash
# 최신 이미지로 업데이트
cd ~/openapi-rag
./scripts/update.sh
```

### 재시작
```bash
cd ~/openapi-rag
docker compose restart
```

### 완전 중지
```bash
cd ~/openapi-rag
docker compose down

# 데이터 포함 삭제 (주의!)
docker compose down -v
```

---

## ❌ 설치 실패 시 대처

### 1. Docker 권한 오류
```bash
# 현재 세션에서 즉시 적용
newgrp docker

# 또는 로그아웃 후 재접속
exit
ssh your-user@your-server-ip
```

### 2. 포트 충돌
```bash
# 80 포트 사용 중인 프로세스 확인
sudo lsof -i :80

# Apache 등 기존 웹서버 중지
sudo systemctl stop apache2
sudo systemctl disable apache2
```

### 3. 메모리 부족
```bash
# 스왑 메모리 추가 (4GB)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 영구 적용
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 4. SSL 발급 실패
```
원인: DNS 전파 지연 또는 포트 80 차단

해결:
1. 도메인 A 레코드 확인 (서버 IP와 일치하는지)
2. 24시간 후 재시도:
   cd ~/openapi-rag
   sudo certbot certonly --nginx -d your-domain.com
   docker compose restart nginx
```

### 5. Ollama 모델 다운로드 실패
```bash
# 수동 다운로드
ollama pull nomic-embed-text

# 다운로드 확인
ollama list
```

---

## 📞 추가 도움

### 로그 파일 위치
```bash
# 설치 로그
cat ~/openwebui-install.log

# 서비스 로그
cd ~/openapi-rag
docker compose logs --tail=100
```

### 설정 파일 위치
```
~/openapi-rag/
├── .env                    # 환경 변수
├── docker-compose.yml      # 컨테이너 구성
├── nginx/conf.d/          # Nginx 설정
├── tools-api/             # RAG API 소스
└── scripts/               # 관리 스크립트
```

### 재설치
```bash
# 기존 설치 완전 제거
cd ~/openapi-rag
docker compose down -v
cd ~
rm -rf ~/openapi-rag

# 스크립트 재실행
./install_openwebui_rag_aws.sh
```

---

## 🎯 권장 설정 조합

### 조합 1: 프로덕션 환경 (권장)
```
✅ 도메인: 있음 (example.com)
✅ Nginx: Y
✅ SSL: Y (Let's Encrypt)
✅ Basic Auth: Y
✅ Ollama: Y (4코어 8GB 이상)
✅ Groq API: Y (백업용)
✅ Fail2ban: Y
✅ UFW: Y
```

### 조합 2: 테스트 환경
```
❌ 도메인: 없음 (IP 접근)
✅ Nginx: Y
❌ SSL: N
❌ Basic Auth: N
✅ Ollama: N
✅ Groq API: Y (필수)
❌ Fail2ban: N
✅ UFW: Y
```

### 조합 3: 저사양 서버
```
❌ 도메인: 없음
✅ Nginx: Y
❌ SSL: N
✅ Basic Auth: Y
❌ Ollama: N (메모리 절약)
✅ Groq API: Y (필수)
✅ Fail2ban: Y
✅ UFW: Y
```

---

## 📚 주요 URL 정리

| URL | 용도 | 인증 |
|-----|------|------|
| `/` | Open WebUI 메인 | WebUI 로그인 |
| `/status` | 보안 현황 대시보드 | 없음 (공개) |
| `/api/docs` | Tools API 문서 | Basic Auth |
| `/qdrant/dashboard` | Qdrant 대시보드 | Basic Auth |
| `/health` | 헬스체크 | 없음 (공개) |

---

## ⚠️ 보안 주의사항

1. **첫 계정 생성 즉시**: 첫 가입자가 관리자이므로 설치 직후 계정 생성
2. **비밀번호 강도**: 최소 12자 이상 권장
3. **SSH 키 인증**: 비밀번호 로그인보다 안전
4. **정기 업데이트**: 매주 일요일 자동 업데이트 (크론 등록됨)
5. **백업 확인**: 매일 새벽 2시 자동 백업 (30일 보관)

---

## ✨ 설치 완료!

이제 다음을 할 수 있습니다:

✅ Ollama/Groq 모델로 AI 채팅  
✅ PDF 문서 업로드 후 RAG 검색  
✅ 멀티 유저 환경 구축  
✅ API를 통한 자동화  

**제작자**: <webmaster@vulva.sex>  
**라이센스**: MIT License
