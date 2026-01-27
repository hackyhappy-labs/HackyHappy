# HackyHappy
“A messy but happy playground for experimental code, scripts, and automation.”
## One-Command Installation

This project is designed to be installed and started using **a single script**.

The script below automatically:
- Sets up Docker-based services
- Starts Qdrant (vector database)
- Connects Ollama for model management
- Configures Groq-based RAG
- Launches OpenWebUI

No manual container setup is required.

### Quick Start

Download and run the script:

```bash
curl -O https://raw.githubusercontent.com/사용자/HackyHappy/main/start-openwebui-with-rag-groq-final.sh
chmod +x start-openwebui-with-rag-groq-final.sh
./start-openwebui-with-rag-groq-final.sh
