#!/usr/bin/env bash
#
# Twilio 번호 keep-alive 설치 스크립트 (대화형)
# ------------------------------------------------
# 실행하면 전화번호와 Twilio 키를 물어보고,
# 스크립트/가상환경/자격증명/cron 을 자동으로 세팅합니다.
#
# 사용법:
#   chmod +x setup_keepalive.sh
#   ./setup_keepalive.sh
#
set -e

echo "=================================================="
echo " Twilio 번호 keep-alive 설치"
echo "=================================================="
echo

# ── 1) 입력받기 ───────────────────────────────
read -rp "유지할 Twilio 번호 (예: +16693337666): " FROM_NUMBER
read -rp "통화를 받을 본인 휴대폰 번호 (예: +821064532023): " TO_NUMBER
read -rp "Twilio Account SID (AC로 시작): " ACCOUNT_SID
read -rsp "Twilio Auth Token (입력해도 화면에 안 보임): " AUTH_TOKEN
echo
echo

# 간단한 검증
if [ -z "$FROM_NUMBER" ] || [ -z "$TO_NUMBER" ] || [ -z "$ACCOUNT_SID" ] || [ -z "$AUTH_TOKEN" ]; then
    echo "오류: 모든 값을 입력해야 합니다. 다시 실행하세요."
    exit 1
fi

# ── 2) 필요한 시스템 패키지 설치 ──────────────
echo "[1/5] 시스템 패키지 확인/설치 (python venv)..."
sudo apt update -y >/dev/null 2>&1 || true
sudo apt install -y python3-venv python3-full >/dev/null 2>&1

# ── 3) 가상환경 + twilio 설치 ─────────────────
echo "[2/5] 파이썬 가상환경 생성 및 twilio 설치..."
if [ ! -d "$HOME/twilio_venv" ]; then
    python3 -m venv "$HOME/twilio_venv"
fi
"$HOME/twilio_venv/bin/pip" install --quiet --upgrade pip
"$HOME/twilio_venv/bin/pip" install --quiet twilio

# ── 4) 자격증명 파일 생성 ─────────────────────
echo "[3/5] 자격증명 파일 생성 (~/.twilio_env)..."
cat > "$HOME/.twilio_env" << EOF
export TWILIO_ACCOUNT_SID="$ACCOUNT_SID"
export TWILIO_AUTH_TOKEN="$AUTH_TOKEN"
EOF
chmod 600 "$HOME/.twilio_env"

# ── 5) keep-alive 스크립트 생성 ───────────────
echo "[4/5] keep-alive 스크립트 생성 (~/twilio_keepalive.py)..."
cat > "$HOME/twilio_keepalive.py" << EOF
#!/usr/bin/env python3
import os, sys, time
from twilio.rest import Client

ACCOUNT_SID = os.environ.get("TWILIO_ACCOUNT_SID")
AUTH_TOKEN  = os.environ.get("TWILIO_AUTH_TOKEN")

FROM_NUMBER = "$FROM_NUMBER"
TO_NUMBER   = "$TO_NUMBER"
NUM_CALLS   = 3
GAP_SECONDS = 40    # 통화 사이 간격 (동시통화/통화중 회피)
KEEPALIVE_TWIML = '<Response><Pause length="15"/><Say>Keep alive.</Say></Response>'

def main():
    if not ACCOUNT_SID or not AUTH_TOKEN:
        sys.exit("오류: TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN 환경변수가 없습니다.")
    client = Client(ACCOUNT_SID, AUTH_TOKEN)

    print(f"[통화] {FROM_NUMBER} -> {TO_NUMBER} : {NUM_CALLS}통 (간격 {GAP_SECONDS}초)")
    for i in range(NUM_CALLS):
        try:
            call = client.calls.create(to=TO_NUMBER, from_=FROM_NUMBER, twiml=KEEPALIVE_TWIML)
            print(f"  통화 {i+1}/{NUM_CALLS} SID={call.sid}")
        except Exception as e:
            print(f"  통화 {i+1} 실패: {e}")
        if i < NUM_CALLS - 1:
            time.sleep(GAP_SECONDS)

    print("완료. Console 의 Calls Log 에서 completed + 12초 이상 확인하세요.")

if __name__ == "__main__":
    main()
EOF

# ── 6) cron 등록 (매월 1일 오전 10시) ─────────
echo "[5/5] cron 등록 (매월 1일 오전 10시)..."
CRON_LINE="0 10 1 * * . ~/.twilio_env && ~/twilio_venv/bin/python ~/twilio_keepalive.py >> ~/keepalive.log 2>&1"
# 기존에 같은 줄이 없으면 추가 (중복 방지)
( crontab -l 2>/dev/null | grep -v "twilio_keepalive.py" ; echo "$CRON_LINE" ) | crontab -

echo
echo "=================================================="
echo " 설치 완료!"
echo "=================================================="
echo " - 스크립트:   ~/twilio_keepalive.py"
echo " - 자격증명:   ~/.twilio_env"
echo " - 가상환경:   ~/twilio_venv"
echo " - cron:       매월 1일 오전 10시 자동 실행"
echo " - 실행 로그:  ~/keepalive.log"
echo
echo " 지금 바로 테스트하려면:"
echo "   . ~/.twilio_env && ~/twilio_venv/bin/python ~/twilio_keepalive.py"
echo
echo " cron 확인:  crontab -l"
echo " 로그 확인:  cat ~/keepalive.log"
echo "=================================================="
