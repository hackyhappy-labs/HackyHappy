# Twilio 번호 keep-alive

[English](KEEPALIVE.md) · 한국어

Twilio는 한 달간 사용되지 않은 전화번호를 회수(reclaim)할 수 있습니다.
이 스크립트는 매월 자동으로 번호에서 짧은 통화를 발생시켜 번호를 "사용 중"
상태로 유지해, 회수를 방지합니다.

## 번호 유지 기준

Twilio 기준으로 다음 중 하나를 한 달간 충족하면 "사용 중"으로 인정됩니다.

- 12초 이상 지속된 `completed` 통화 3통 이상
- 문자(SMS) 3건 이상

이 스크립트는 위 기준을 채우기 위해 매월 통화 3통을 겁니다.
(문자는 미국 번호의 A2P 10DLC 등록 문제로 기본 비활성화되어 있습니다.)

## 설치 방법

```bash
chmod +x setup_keepalive.sh
./setup_keepalive.sh
```

실행하면 아래 4가지를 물어봅니다. 입력하면 자동으로 세팅됩니다.

- 유지할 Twilio 번호 (국가코드 포함, 예: `+1`로 시작)
- 통화를 받을 본인 휴대폰 번호 (국가코드 포함, 한국은 `+82`로 시작)
- Twilio Account SID (`AC`로 시작)
- Twilio Auth Token (입력해도 화면에 표시되지 않음)

스크립트가 자동으로 처리하는 것:

1. 시스템 패키지 설치 (`python3-venv`, `python3-full`)
2. 파이썬 가상환경 생성 (`~/twilio_venv`)
3. `twilio` 라이브러리 설치
4. 자격증명 파일 생성 (`~/.twilio_env`, 권한 600)
5. keep-alive 스크립트 생성 (`~/twilio_keepalive.py`)
6. cron 등록 (매월 1일 오전 10시 자동 실행)

## 요구 사항

- 인터넷 연결 (twilio 다운로드)
- sudo 권한 (패키지 설치)

## 설치 후 테스트

설치가 끝나면 바로 한 번 실행해서 통화가 오는지 확인하세요.

```bash
. ~/.twilio_env && ~/twilio_venv/bin/python ~/twilio_keepalive.py
```

휴대폰으로 통화 3통이 순서대로 걸려오면 정상입니다.
Twilio Console → Monitor → Logs → Calls 에서 3통이
`completed` + 12초 이상으로 찍혔는지 확인하세요.

## 확인 명령

```bash
crontab -l              # cron 등록 확인
cat ~/keepalive.log     # 실행 로그 확인
```

## 설정 변경

번호나 실행 주기를 바꾸려면 스크립트를 다시 실행하거나,
아래 파일을 직접 수정하세요.

- 통화 간격/횟수: `~/twilio_keepalive.py` 의 `NUM_CALLS`, `GAP_SECONDS`
- 실행 주기: `crontab -e` 에서 시간 필드 수정
  - 매월 1일: `0 10 1 * *`
  - 매월 1일·15일 (더 안전): `0 10 1,15 * *`

## 삭제 / 초기화

keep-alive 관련 항목(스크립트·cron·가상환경·키·로그)을 모두 제거하려면
`uninstall_keepalive.sh` 를 실행합니다.

```bash
chmod +x uninstall_keepalive.sh
./uninstall_keepalive.sh
```

실행하면 확인을 물어보고, `yes` 를 입력하면 아래를 삭제합니다.

- cron 등록 (keep-alive 줄만 제거)
- `~/twilio_keepalive.py`
- `~/.twilio_env` (Twilio 키)
- `~/twilio_venv/` (가상환경)
- `~/keepalive.log`

스크립트 없이 직접 지우려면:

```bash
crontab -l | grep -v "twilio_keepalive.py" | crontab -   # cron 제거
rm -f  ~/twilio_keepalive.py
rm -f  ~/.twilio_env
rm -rf ~/twilio_venv
rm -f  ~/keepalive.log
crontab -l                                                # 확인
```

> `python3-venv`, `python3-full`(apt 시스템 패키지)은 다른 프로그램도 쓸 수 있어
> 자동 삭제하지 않습니다. 정말 지우려면 `sudo apt remove python3-venv python3-full`
> (다른 프로그램이 사용 중일 수 있으니 권장하지 않음).

---

## 보안 주의

이 저장소에는 `setup_keepalive.sh` 와 `uninstall_keepalive.sh` 를 올립니다.
(설치 시 키를 입력받으므로 파일 자체에는 비밀 정보가 없습니다.)

서버에 생성되는 아래 파일에는 실제 키/번호가 들어 있으므로
**절대 커밋하지 마세요.**

- `~/.twilio_env` (Twilio 키)
- `~/twilio_keepalive.py` (전화번호 포함)
- `~/keepalive.log` (실행 기록)

`.gitignore` 예시:

```
.twilio_env
*.log
twilio_venv/
twilio_keepalive.py
```
