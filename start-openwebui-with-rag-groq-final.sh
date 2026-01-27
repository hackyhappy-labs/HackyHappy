#!/bin/bash
# =============================================================================
# 프로젝트명: OpenWebUI RAG 설치 스크립트
# 제작자: <webmaster@vulva.sex>
# 제작일: 2026-01-26
# 설명: Docker + Ollama + Groq + Qdrant 기반 설치/자동화 스크립트
# 라이센스: MIT License
# =============================================================================

############################################
# 0. 시스템 사양 자동 감지
############################################
echo "🔍 시스템 사양 감지 중..."

CPU_CORES=$(nproc 2>/dev/null || echo 1)

TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
AVAILABLE_RAM_MB=$(free -m | awk '/^Mem:/{print $7}')

# 값이 비어있을 경우 대비
TOTAL_RAM_MB=${TOTAL_RAM_MB:-0}
AVAILABLE_RAM_MB=${AVAILABLE_RAM_MB:-0}

TOTAL_RAM=$((TOTAL_RAM_MB / 1024))
AVAILABLE_RAM=$((AVAILABLE_RAM_MB / 1024))

echo "   CPU 코어: ${CPU_CORES}개"
echo "   총 메모리: ${TOTAL_RAM}GB"
echo "   사용 가능: ${AVAILABLE_RAM}GB"

# 성능 등급 판단
if [ $CPU_CORES -ge 6 ] && [ $TOTAL_RAM -ge 16 ]; then
  PERFORMANCE="HIGH"
  PERF_NAME="고성능 🚀"
  QDRANT_RETRIES=20
  QDRANT_INTERVAL=2
  TOOLS_RETRIES=20
  TOOLS_INTERVAL=2
  WEBUI_RETRIES=30
  WEBUI_INTERVAL=2
  MEMORY_QDRANT="1G"
  MEMORY_TOOLS="2G"
  MEMORY_WEBUI="4G"
elif [ $CPU_CORES -ge 4 ] && [ $TOTAL_RAM -ge 8 ]; then
  PERFORMANCE="MEDIUM_HIGH"
  PERF_NAME="중상급 💪"
  QDRANT_RETRIES=30
  QDRANT_INTERVAL=3
  TOOLS_RETRIES=30
  TOOLS_INTERVAL=3
  WEBUI_RETRIES=40
  WEBUI_INTERVAL=3
  MEMORY_QDRANT="768M"
  MEMORY_TOOLS="1.5G"
  MEMORY_WEBUI="3G"
elif [ $CPU_CORES -ge 2 ] && [ $TOTAL_RAM -ge 4 ]; then
  PERFORMANCE="MEDIUM"
  PERF_NAME="중급 📊"
  QDRANT_RETRIES=40
  QDRANT_INTERVAL=4
  TOOLS_RETRIES=40
  TOOLS_INTERVAL=4
  WEBUI_RETRIES=60
  WEBUI_INTERVAL=4
  MEMORY_QDRANT="512M"
  MEMORY_TOOLS="1G"
  MEMORY_WEBUI="2G"
else
  PERFORMANCE="LOW"
  PERF_NAME="저사양 🐢"
  QDRANT_RETRIES=60
  QDRANT_INTERVAL=5
  TOOLS_RETRIES=60
  TOOLS_INTERVAL=5
  WEBUI_RETRIES=120
  WEBUI_INTERVAL=5
  MEMORY_QDRANT="384M"
  MEMORY_TOOLS="768M"
  MEMORY_WEBUI="1.5G"
fi

echo ""
echo "┌────────────────────────────────────────────┐"
echo "📊 감지된 성능: ${PERF_NAME}"
echo "└────────────────────────────────────────────┘"
echo "   예상 설치 시간: $(( (QDRANT_RETRIES * QDRANT_INTERVAL + TOOLS_RETRIES * TOOLS_INTERVAL + WEBUI_RETRIES * WEBUI_INTERVAL) / 60 ))분 이내"
echo "   메모리 할당: Qdrant(${MEMORY_QDRANT}), Tools(${MEMORY_TOOLS}), WebUI(${MEMORY_WEBUI})"
echo "└────────────────────────────────────────────┘"
echo ""

############################################
# 1. root 실행 방지
############################################
if [ "$EUID" -eq 0 ]; then
  echo "❌ root로 실행하지 마세요. 일반 사용자로 실행하세요."
  exit 1
fi

############################################
# 2. Docker 자동 설치
############################################
if ! command -v docker >/dev/null; then
  echo "⚙️ Docker 미설치 → 자동 설치"
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker $USER
  echo "⚠️ 로그아웃 후 재접속 또는 newgrp docker 필요"
  echo "❌ Docker 설치 완료. 다시 로그인한 후 스크립트를 재실행하세요."
  exit 0
fi

# Docker 서비스 확인
if ! sudo systemctl is-active --quiet docker; then
  echo "⚙️ Docker 서비스 시작 중..."
  sudo systemctl enable --now docker
  sleep 3
fi

# Docker 권한 확인
if ! docker ps >/dev/null 2>&1; then
  echo "❌ Docker 권한 없음. 다음 명령어 실행 후 재접속:"
  echo "   sudo usermod -aG docker $USER"
  echo "   newgrp docker"
  exit 1
fi

############################################
# 3. Ollama 자동 감지 및 설치
############################################
echo ""
echo "🔍 Ollama 설치 상태 확인 중..."

OLLAMA_INSTALLED=false
OLLAMA_RUNNING=false

# Ollama 설치 여부 확인
if command -v ollama >/dev/null 2>&1; then
  OLLAMA_INSTALLED=true
  echo "   ✅ Ollama 이미 설치됨"
  
  # Ollama 서버 실행 여부 확인
  if pgrep -x "ollama" >/dev/null; then
    OLLAMA_RUNNING=true
    echo "   ✅ Ollama 서버 실행 중"
  else
    echo "   ⚠️ Ollama 서버 중지 상태"
  fi
else
  echo "   ℹ️ Ollama 미설치"
fi

# Ollama 설치/사용 여부 결정
if [ "$OLLAMA_INSTALLED" = true ]; then
  # 이미 설치된 경우 - 사용 여부만 묻기
  echo ""
  echo "💡 Ollama가 이미 설치되어 있습니다."
  read -p "🤖 Ollama를 사용하시겠습니까? (Y/n): " USE_OLLAMA_INPUT
  USE_OLLAMA_INPUT=${USE_OLLAMA_INPUT:-Y}
  
  if [[ "$USE_OLLAMA_INPUT" =~ ^[Yy]$ ]]; then
    USE_OLLAMA=true
    
    # 서버가 중지되어 있으면 시작
    if [ "$OLLAMA_RUNNING" = false ]; then
      echo "⚙️ Ollama 서버 시작 중..."
      nohup ollama serve > /tmp/ollama.log 2>&1 &
      sleep 5
      echo "   ✅ Ollama 서버 시작 완료"
    fi
    
    # Systemd 서비스 등록 (재부팅 시 자동 시작)
    echo "⚙️ Ollama 자동 시작 설정 중..."
    if sudo systemctl is-enabled ollama >/dev/null 2>&1; then
      echo "   ✅ Ollama 자동 시작 이미 활성화됨"
    else
      if sudo systemctl enable ollama 2>/dev/null; then
        echo "   ✅ Ollama 자동 시작 활성화"
      else
        echo "   ⚠️ Ollama 자동 시작 설정 실패 (수동 관리 필요)"
      fi
    fi
    
    # 필요한 모델 확인 및 다운로드
    echo "📋 임베딩 모델 확인 중..."
    if ! ollama list | grep -q "nomic-embed-text"; then
      echo "📥 nomic-embed-text 모델 다운로드 중..."
      ollama pull nomic-embed-text || echo "⚠️ 모델 다운로드 실패 (나중에 재시도 가능)"
    else
      echo "   ✅ nomic-embed-text 모델 이미 존재"
    fi
  else
    USE_OLLAMA=false
    echo "⭐️ Ollama 사용 안 함"
  fi
  
else
  # 설치되지 않은 경우 - 성능별 권장사항 제시
  echo ""
  if [ "$PERFORMANCE" = "HIGH" ] || [ "$PERFORMANCE" = "MEDIUM_HIGH" ]; then
    echo "💡 ${PERF_NAME} 시스템 → Ollama 설치 권장 (로컬 임베딩)"
    read -p "🤖 Ollama를 설치하시겠습니까? (Y/n): " INSTALL_OLLAMA
    INSTALL_OLLAMA=${INSTALL_OLLAMA:-Y}
  else
    echo "💡 ${PERF_NAME} 시스템 → Groq API 사용 권장 (리소스 절약)"
    read -p "🤖 Ollama를 설치하시겠습니까? (y/N): " INSTALL_OLLAMA
    INSTALL_OLLAMA=${INSTALL_OLLAMA:-N}
  fi
  
  if [[ "$INSTALL_OLLAMA" =~ ^[Yy]$ ]]; then
    echo "⚙️ Ollama 설치 중..."
    curl -fsSL https://ollama.com/install.sh | sh
    
    echo "⚙️ Ollama 자동 시작 설정 중..."
    if sudo systemctl enable ollama 2>/dev/null && sudo systemctl start ollama 2>/dev/null; then
      sleep 5
      echo "   ✅ Ollama 서비스 활성화 완료"
    else
      echo "   ⚠️ Ollama 서비스 등록 실패, 수동으로 시작합니다..."
      nohup ollama serve > /tmp/ollama.log 2>&1 &
      sleep 5
    fi
    
    echo "📥 nomic-embed-text 모델 다운로드 중..."
    ollama pull nomic-embed-text || echo "⚠️ 모델 다운로드 실패 (나중에 재시도 가능)"
    
    USE_OLLAMA=true
    echo "   ✅ Ollama 설치 및 설정 완료"
  else
    USE_OLLAMA=false
    echo "⭐️ Ollama 설치 건너뜀"
  fi
fi

############################################
# 4. GPU 감지
############################################
if command -v nvidia-smi >/dev/null 2>&1; then
  OPEN_WEBUI_IMAGE="ghcr.io/open-webui/open-webui:cuda"
  echo "✅ NVIDIA GPU 감지 (CUDA)"
else
  OPEN_WEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"
  echo "ℹ️ GPU 없음 (CPU 모드)"
fi

############################################
# 5. Groq API Key (선택 입력, 저장 가능)
############################################
echo ""
echo "┌────────────────────────────────────────────┐"
echo "🔑 Groq API Key 설정 (선택사항)"
echo "└────────────────────────────────────────────┘"

if [ "$USE_OLLAMA" = false ]; then
  echo "⚠️  Ollama를 사용하지 않으므로 Groq API 키 권장"
  echo "   (없으면 모델을 사용할 수 없습니다)"
  echo ""
fi

read -t 60 -p "🔑 Groq API Key 입력 (60초 내 Enter=건너뜀): " GROQ_API_KEY || true
GROQ_API_KEY=$(echo "$GROQ_API_KEY" | xargs)  # 공백 제거

if [ -n "$GROQ_API_KEY" ]; then
  echo "✅ Groq API Key 저장됨"
  USE_GROQ=true
else
  echo "⭐️ Groq API Key 건너뜀"
  USE_GROQ=false
  
  # Ollama도 없고 Groq도 없으면 경고
  if [ "$USE_OLLAMA" = false ]; then
    echo ""
    echo "⚠️  경고: Ollama와 Groq 모두 비활성화됩니다."
    echo "   설치 후 Settings에서 API 키를 추가하거나"
    echo "   Ollama를 설치하여 사용할 수 있습니다."
    echo ""
    read -t 30 -p "   계속하시겠습니까? (30초 후 자동 진행) [Y/n]: " CONTINUE || CONTINUE="Y"
    CONTINUE=${CONTINUE:-Y}
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]] && [ "$CONTINUE" != "" ]; then
      echo "❌ 설치 중단됨"
      exit 0
    fi
  fi
fi

############################################
# 6. 작업 디렉토리 초기화
############################################
BASE_DIR="$HOME/openapi-rag"
if [ -d "$BASE_DIR" ]; then
  echo "🧹 기존 설치 제거 중..."
  cd "$BASE_DIR"
  docker compose down -v 2>/dev/null || true
  cd ~
  rm -rf "$BASE_DIR"
fi

mkdir -p "$BASE_DIR/tools-api/data"
cd "$BASE_DIR"

############################################
# 7. .env
############################################
cat > .env <<EOF
# Qdrant 설정
VECTOR_DB=qdrant
QDRANT_URI=http://qdrant:6333
QDRANT_URL=http://qdrant:6333
QDRANT_COLLECTION=openapi_rag
EOF

if [ "$USE_OLLAMA" = true ]; then
cat >> .env <<EOF

# Ollama 설정 (임베딩용)
OLLAMA_BASE_URL=http://host.docker.internal:11434
OLLAMA_EMBED_MODEL=nomic-embed-text
EOF
fi

if [ "$USE_GROQ" = true ] && [ -n "$GROQ_API_KEY" ]; then
cat >> .env <<EOF

# Groq API 설정
OPENAI_API_KEY=$GROQ_API_KEY
OPENAI_API_BASE_URL=https://api.groq.com/openai/v1
EOF
fi

chmod 600 .env

############################################
# 8. OpenAPI Tool Server
############################################
cat > tools-api/requirements.txt <<EOF
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
requests==2.31.0
python-multipart==0.0.6
pypdf==3.17.4
qdrant-client==1.7.0
numpy==1.26.3
ollama==0.1.6
EOF

# 성능별 재시도 횟수 설정
PYTHON_RETRIES=$((QDRANT_RETRIES / 2))

cat > tools-api/main.py <<EOF
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os, uuid, time
from pypdf import PdfReader
import ollama
from qdrant_client import QdrantClient
from qdrant_client.models import VectorParams, Distance, PointStruct

app = FastAPI(
    title="OpenAPI RAG Tool Server",
    description="Standard OpenAPI-based Retrieval-Augmented Generation Tool Server (Qdrant + Ollama)",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# 환경 변수 설정
QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
COLLECTION = os.getenv("QDRANT_COLLECTION", "openapi_rag")
MODEL = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://host.docker.internal:11434")
DATA_DIR = "/app/data"

# Qdrant 클라이언트 초기화 (성능별 재시도)
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

# 컬렉션 생성
if client:
    try:
        collections = [c.name for c in client.get_collections().collections]
        if COLLECTION not in collections:
            client.create_collection(
                collection_name=COLLECTION,
                vectors_config=VectorParams(size=768, distance=Distance.COSINE),
            )
            print(f"✅ 컬렉션 생성: {COLLECTION}")
        else:
            print(f"✅ 기존 컬렉션 사용: {COLLECTION}")
    except Exception as e:
        print(f"❌ 컬렉션 생성 실패: {e}")

def embed(text: str):
    try:
        ollama_client = ollama.Client(host=OLLAMA_BASE_URL)
        response = ollama_client.embeddings(model=MODEL, prompt=text)
        return response["embedding"]
    except Exception as e:
        print(f"❌ 임베딩 오류: {e}")
        raise HTTPException(status_code=500, detail=f"Embedding error: {str(e)}")

@app.post("/documents/upload", summary="Upload document for RAG indexing")
async def upload_pdf(file: UploadFile = File(...)):
    if not client:
        raise HTTPException(status_code=503, detail="Qdrant client not initialized")
    
    try:
        path = f"{DATA_DIR}/{file.filename}"
        with open(path, "wb") as f:
            content = await file.read()
            f.write(content)
        
        print(f"📄 파일 저장: {file.filename}")

        reader = PdfReader(path)
        text = "".join(p.extract_text() or "" for p in reader.pages)
        
        if not text.strip():
            raise HTTPException(status_code=400, detail="PDF 텍스트 추출 실패")
        
        print(f"📝 텍스트 추출: {len(text)} 문자")

        chunks = []
        chunk_size = 1000
        overlap = 100
        for i in range(0, len(text), chunk_size - overlap):
            chunk = text[i:i + chunk_size].strip()
            if chunk:
                chunks.append(chunk)
        
        print(f"✂️ 청크 분할: {len(chunks)}개")

        points = []
        for idx, chunk in enumerate(chunks):
            try:
                vector = embed(chunk)
                points.append(
                    PointStruct(
                        id=str(uuid.uuid4()),
                        vector=vector,
                        payload={"text": chunk, "source": file.filename, "chunk_index": idx},
                    )
                )
                if (idx + 1) % 10 == 0:
                    print(f"🔢 임베딩: {idx + 1}/{len(chunks)}")
            except Exception as e:
                print(f"⚠️ 청크 {idx} 실패: {e}")
                continue

        if not points:
            raise HTTPException(status_code=500, detail="임베딩 실패")

        client.upsert(collection_name=COLLECTION, points=points)
        print(f"💾 저장 완료: {len(points)}개")
        
        return {
            "status": "success",
            "filename": file.filename,
            "total_chunks": len(chunks),
            "indexed_chunks": len(points),
            "collection": COLLECTION
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ 업로드 오류: {e}")
        raise HTTPException(status_code=500, detail=f"Upload error: {str(e)}")

class SearchQuery(BaseModel):
    query: str
    top_k: int = 3

@app.post("/rag/search", summary="Semantic search for RAG")
def rag_search(search: SearchQuery):
    if not client:
        raise HTTPException(status_code=503, detail="Qdrant client not initialized")
    
    try:
        query_vector = embed(search.query)
        hits = client.search(
            collection_name=COLLECTION,
            query_vector=query_vector,
            limit=search.top_k,
        )
        
        results = [
            {
                "text": h.payload.get("text", ""),
                "source": h.payload.get("source", ""),
                "chunk_index": h.payload.get("chunk_index", 0),
                "score": h.score
            }
            for h in hits
        ]
        
        return {"query": search.query, "results": results, "count": len(results)}
        
    except Exception as e:
        print(f"❌ 검색 오류: {e}")
        raise HTTPException(status_code=500, detail=f"Search error: {str(e)}")

@app.get("/health", summary="Health check")
def health():
    try:
        if not client:
            return {"status": "unhealthy", "error": "Qdrant client not initialized"}
        client.get_collections()
        return {"status": "healthy", "qdrant_url": QDRANT_URL, "collection": COLLECTION, "embed_model": MODEL}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

@app.get("/", summary="API Info")
def root():
    return {
        "service": "OpenAPI RAG Tool Server",
        "version": "1.0.0",
        "endpoints": {
            "docs": "/docs",
            "openapi": "/openapi.json",
            "upload": "/documents/upload",
            "search": "/rag/search",
            "health": "/health"
        }
    }
EOF

cat > tools-api/Dockerfile <<EOF
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y gcc curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
RUN mkdir -p /app/data
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

############################################
# 9. docker-compose.yml (수정 - Ollama 모델 표시 지원)
############################################
SECRET_KEY=$(openssl rand -hex 32)

cat > docker-compose.yml <<EOF
services:
  qdrant:
    image: qdrant/qdrant:latest
    volumes:
      - qdrant-data:/qdrant/storage
    ports:
      - "6333:6333"
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: ${MEMORY_QDRANT}

  openapi-tools:
    build: ./tools-api
    env_file: .env
    volumes:
      - ./tools-api/data:/app/data
    ports:
      - "8000:8000"
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
      - VECTOR_DB=qdrant
      - QDRANT_URI=http://qdrant:6333
EOF

# Ollama 설정 추가 (USE_OLLAMA에 따라)
if [ "$USE_OLLAMA" = true ]; then
cat >> docker-compose.yml <<EOF
      - ENABLE_OLLAMA_API=true
      - OLLAMA_BASE_URL=http://host.docker.internal:11434
EOF
else
cat >> docker-compose.yml <<EOF
      - ENABLE_OLLAMA_API=false
EOF
fi

# Groq API 설정 추가
if [ "$USE_GROQ" = true ] && [ -n "$GROQ_API_KEY" ]; then
cat >> docker-compose.yml <<EOF
      - ENABLE_OPENAI_API=true
      - OPENAI_API_KEY=$GROQ_API_KEY
      - OPENAI_API_BASE_URL=https://api.groq.com/openai/v1
      - DEFAULT_MODELS=llama-3.3-70b-versatile
EOF
else
cat >> docker-compose.yml <<EOF
      - ENABLE_OPENAI_API=false
EOF
fi

# 나머지 open-webui 설정
cat >> docker-compose.yml <<EOF
    volumes:
      - open-webui-data:/app/backend/data
    ports:
      - "0.0.0.0:3000:8080"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on:
      - qdrant
      - openapi-tools
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: ${MEMORY_WEBUI}

volumes:
  qdrant-data:
  open-webui-data:
EOF
      
############################################
# 10. 실행 (성능별 대기 시간)
############################################
echo ""
echo "🔨 Docker 이미지 빌드 중..."
docker compose build

echo ""
echo "🚀 컨테이너 시작..."
docker compose up -d

echo ""
echo "┌────────────────────────────────────────────┐"
echo "⏳ ${PERF_NAME} - 서비스 준비 대기"
echo "└────────────────────────────────────────────┘"

# Qdrant 대기
echo ""
echo "📦 1/3 Qdrant 시작 중..."
for i in $(seq 1 $QDRANT_RETRIES); do
  if docker compose exec -T qdrant timeout 3 curl -s http://localhost:6333/collections >/dev/null 2>&1; then
    echo "   ✅ Qdrant 준비 완료! (${i}/${QDRANT_RETRIES})"
    break
  fi
  printf "   ⏳ 대기 중... %d/%d\r" $i $QDRANT_RETRIES
  sleep $QDRANT_INTERVAL
done

# OpenAPI Tools 대기
echo ""
echo "🧠 2/3 OpenAPI Tools 시작 중..."
for i in $(seq 1 $TOOLS_RETRIES); do
  if timeout 3 curl -s http://localhost:8000/health >/dev/null 2>&1; then
    echo "   ✅ OpenAPI Tools 준비 완료! (${i}/${TOOLS_RETRIES})"
    break
  fi
  printf "   ⏳ 대기 중... %d/%d\r" $i $TOOLS_RETRIES
  sleep $TOOLS_INTERVAL
done

# Open WebUI 대기
echo ""
echo "🌐 3/3 Open WebUI 시작 중..."
for i in $(seq 1 $WEBUI_RETRIES); do
  if docker compose logs open-webui 2>&1 | grep -q "Application startup complete\|Uvicorn running"; then
    sleep 3
    if timeout 3 curl -s http://localhost:3000 >/dev/null 2>&1; then
      echo "   ✅ Open WebUI 준비 완료! (${i}/${WEBUI_RETRIES})"
      break
    fi
  fi
  printf "   ⏳ 대기 중... %d/%d\r" $i $WEBUI_RETRIES
  sleep $WEBUI_INTERVAL
done

echo ""
echo "└────────────────────────────────────────────┘"

# 최종 상태
echo ""
echo "📊 컨테이너 상태:"
docker compose ps

echo ""
echo "┌────────────────────────────────────────────┐"
echo "🎉 설치 완료!"
echo "└────────────────────────────────────────────┘"
echo ""
echo "📊 설치된 구성:"
if [ "$USE_OLLAMA" = true ]; then
  echo "   ✅ Ollama: 활성화 (로컬 모델)"
else
  echo "   ⭐️ Ollama: 비활성화"
fi
if [ "$USE_GROQ" = true ]; then
  echo "   ✅ Groq API: 활성화 (클라우드 모델)"
else
  echo "   ⭐️ Groq API: 비활성화"
fi
echo ""
echo "🌐 서비스 URL:"
echo "   Open WebUI        : http://localhost:3000"
echo "   OpenAPI Tool Docs : http://localhost:8000/docs"
echo "   Qdrant Dashboard  : http://localhost:6333/dashboard"
echo ""
echo "💡 사용 방법:"
echo "   1. http://localhost:3000 접속"
echo "   2. 계정 생성 (첫 계정이 관리자)"

if [ "$USE_OLLAMA" = true ] && [ "$USE_GROQ" = true ]; then
  echo "   3. Settings → Models에서 Ollama + Groq 모델 모두 표시됨"
  echo "   4. 채팅 시 원하는 모델 선택 가능"
elif [ "$USE_OLLAMA" = true ]; then
  echo "   3. Settings → Models에서 Ollama 로컬 모델만 표시됨"
  echo "   4. Groq 모델 추가: Settings → Connections → OpenAI에서 API 키 입력"
elif [ "$USE_GROQ" = true ]; then
  echo "   3. Settings → Models에서 Groq 클라우드 모델만 표시됨"
  echo "   4. Ollama 추가: 호스트에서 'ollama serve' 실행 후 재시작"
else
  echo "   3. ⚠️  현재 사용 가능한 모델 없음"
  echo "   4. Settings → Connections에서 API 키 추가 또는"
  echo "      호스트에서 Ollama 설치 후 컨테이너 재시작"
fi

echo ""
echo "📚 RAG 사용 방법:"
echo ""
echo "   1️⃣  PDF 업로드:"
echo "      curl -X POST http://localhost:8000/documents/upload \\"
echo "           -F 'file=@document.pdf'"
echo ""
echo "   2️⃣  Open WebUI에서 사용:"
echo "      입력창에 @rag_search : [검색어]에 대해 찾아줘"
echo ""
echo "   3️⃣  RAG 상태 확인:"
echo "      curl http://localhost:8000/health"
echo ""
echo ""
echo "🔧 관리 명령어:"
echo "   cd ~/openapi-rag"
echo "   docker compose logs -f          # 전체 로그 확인"
echo "   docker compose logs -f open-webui   # WebUI 로그만"
echo "   docker compose restart          # 재시작"
echo "   docker compose down             # 중지"
echo "   docker compose down -v          # 중지 + 데이터 삭제"
echo ""
if [ "$USE_OLLAMA" = true ]; then
echo "🤖 Ollama 서비스 관리:"
echo "   systemctl status ollama  # Ollama 상태 확인"
echo "   systemctl restart ollama # Ollama 재시작"
echo "   sudo journalctl -u ollama -f  # Ollama 로그"
echo "   ollama list  # 설치된 모델 확인"
echo ""
fi
echo "└────────────────────────────────────────────┘"
