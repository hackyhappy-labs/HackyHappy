# HackyHappy 😄

**One-click auto-run script for a Groq-powered RAG AI environment**

This repository provides a **one-touch automation script** that sets up and runs a complete  
**Groq + RAG + Docker + Ollama +  Qdrant + OpenWebUI** AI environment.

No complex manual setup.  
Just run one script and start using your AI stack.

---

## 🚀 What This Project Does

With a single script, this project will automatically:

- Start required Docker services
- Launch **Qdrant** (vector database)
- Connect **Ollama** for local model management
- Configure **Groq-based RAG**
- Run **OpenWebUI** for a ChatGPT-like web interface

Designed for:
- Developers
- AI hobbyists
- Self-hosted RAG experiments
- Quick demos and testing

---

## 📦 Included Script

- `start-openwebui-with-rag-groq-final.sh`  
  → One-click auto-run script for the full AI stack

---

## ⚙️ Requirements

Before running the script, make sure you have:

- Linux environment
- Docker
- Docker Compose
- Bash
- Groq API Key (Optional, for Groq-based RAG)


> ⚠️ Windows users should use **WSL2 (Ubuntu recommended)**

---

## 🔑 Groq API Key Setup

(Optional) Groq API Key  
Get your API key from: https://console.groq.com/keys

The generated `.env` file is located in the project directory.  
The script will automatically create the `.env` file; if it does not exist, please create it manually.

```env
GROQ_API_KEY=your_groq_api_key_here

🛠 Installation & Usage
Option 1: One-Click Install (Recommended)
curl -O https://raw.githubusercontent.com/hackyhappy-labs/HackyHappy/main/start-openwebui-with-rag-groq-final.sh
chmod +x start-openwebui-with-rag-groq-final.sh
./start-openwebui-with-rag-groq-final.sh

Option 2: Clone Repository
git clone https://github.com/hackyhappy-labs/HackyHappy.git
cd HackyHappy
chmod +x start-openwebui-with-rag-groq-final.sh
./start-openwebui-with-rag-groq-final.sh

🌐 Access OpenWebUI
OpenWebUI: http://localhost:3000
RAG API Documentation: http://localhost:8000/docs
Database Dashboard (Qdrant): http://localhost:6333/dashboard

📚 How to Use RAG
1️⃣ Upload a PDF
curl -X POST http://localhost:8000/upload_pdf -F "file=@document.pdf"

2️⃣ Use it in Open WebUI

In the input box, type:

@rag_search : Please search for [your keyword]

3️⃣ Check RAG Service Status
curl http://localhost:8000/health




