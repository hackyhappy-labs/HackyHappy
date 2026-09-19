#!/usr/bin/env bash
#
# Twilio keep-alive 초기화(삭제) 스크립트
# ------------------------------------------------
# setup_keepalive.sh 로 설치한 것들을 모두 제거합니다.
#   - cron 등록 제거
#   - keep-alive 스크립트 삭제 (~/twilio_keepalive.py)
#   - 자격증명 파일 삭제 (~/.twilio_env)
#   - 가상환경 삭제 (~/twilio_venv)
#   - 실행 로그 삭제 (~/keepalive.log)
#
# 사용법:
#   chmod +x uninstall_keepalive.sh
#   ./uninstall_keepalive.sh
#
echo "=================================================="
echo " Twilio keep-alive 초기화(삭제)"
echo "=================================================="
echo
echo "다음 항목을 삭제합니다:"
echo "  - cron 등록 (twilio_keepalive.py)"
echo "  - ~/twilio_keepalive.py"
echo "  - ~/.twilio_env  (Twilio 키)"
echo "  - ~/twilio_venv/ (가상환경)"
echo "  - ~/keepalive.log"
echo
read -rp "정말 삭제할까요? (yes 입력 시 진행): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "취소했습니다. 아무것도 삭제하지 않았습니다."
    exit 0
fi
echo

# 1) cron 제거 (twilio_keepalive.py 가 든 줄만 삭제)
echo "[1/5] cron 등록 제거..."
if crontab -l 2>/dev/null | grep -q "twilio_keepalive.py"; then
    crontab -l 2>/dev/null | grep -v "twilio_keepalive.py" | crontab -
    echo "      → cron 줄 삭제됨"
else
    echo "      → cron에 해당 항목 없음 (건너뜀)"
fi

# 2) keep-alive 스크립트 삭제
echo "[2/5] ~/twilio_keepalive.py 삭제..."
rm -f "$HOME/twilio_keepalive.py" && echo "      → 삭제됨"

# 3) 자격증명 파일 삭제
echo "[3/5] ~/.twilio_env 삭제..."
rm -f "$HOME/.twilio_env" && echo "      → 삭제됨"

# 4) 가상환경 삭제
echo "[4/5] ~/twilio_venv 삭제..."
rm -rf "$HOME/twilio_venv" && echo "      → 삭제됨"

# 5) 로그 삭제
echo "[5/5] ~/keepalive.log 삭제..."
rm -f "$HOME/keepalive.log" && echo "      → 삭제됨"

echo
echo "=================================================="
echo " 초기화 완료 — keep-alive 관련 항목이 모두 삭제되었습니다."
echo "=================================================="
echo
echo " (참고) 아래는 자동 삭제하지 않습니다. 필요하면 직접 지우세요:"
echo "   - apt로 설치한 python3-venv, python3-full (시스템 공용이라 그대로 둠)"
echo "   - setup_keepalive.sh, uninstall_keepalive.sh (스크립트 파일 자체)"
echo
echo " cron이 지워졌는지 확인:  crontab -l"
echo "=================================================="
