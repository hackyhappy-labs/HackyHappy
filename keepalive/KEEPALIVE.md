# Twilio Number Keep-Alive

English · [한국어](KEEPALIVE_ko.md)

Twilio may reclaim phone numbers that go unused for a month. This script
places a few short calls from your number every month to keep it marked as
"in use," preventing reclamation.

## Retention criteria

Twilio considers a number "in use" if, within the last month, it meets
either of these:

- At least 3 `completed` calls lasting 12 seconds or longer
- At least 3 SMS messages

This script places 3 calls per month to satisfy the criteria.
(SMS is disabled by default due to US A2P 10DLC registration requirements.)

## Installation

```bash
chmod +x setup_keepalive.sh
./setup_keepalive.sh
```

Running it prompts for the following 4 values. It then sets everything up
automatically:

- Twilio number to keep alive (e.g. `+16693337666`)
- Your mobile number to receive the calls (e.g. `+821064532023`)
- Twilio Account SID (starts with `AC`)
- Twilio Auth Token (hidden while typing)

What the script does automatically:

1. Installs system packages (`python3-venv`, `python3-full`)
2. Creates a Python virtual environment (`~/twilio_venv`)
3. Installs the `twilio` library
4. Creates the credentials file (`~/.twilio_env`, permission 600)
5. Creates the keep-alive script (`~/twilio_keepalive.py`)
6. Registers a cron job (runs on the 1st of each month at 10:00 AM)

## Requirements

- Internet connection (to download twilio)
- sudo privileges (to install packages)

## Test after installation

Once installed, run it once to confirm the calls come through.

```bash
. ~/.twilio_env && ~/twilio_venv/bin/python ~/twilio_keepalive.py
```

You should receive 3 calls on your phone, one after another. Check
Twilio Console → Monitor → Logs → Calls to confirm all 3 are logged as
`completed` with a duration of 12 seconds or more.

## Useful commands

```bash
crontab -l              # check the cron job
cat ~/keepalive.log     # check the run log
```

## Changing settings

To change the number or schedule, re-run the script or edit these directly:

- Call interval/count: `NUM_CALLS`, `GAP_SECONDS` in `~/twilio_keepalive.py`
- Schedule: edit the time fields via `crontab -e`
  - Monthly (1st): `0 10 1 * *`
  - Monthly (1st & 15th, safer): `0 10 1,15 * *`

## Security notes

Only `setup_keepalive.sh` is committed to this repository.
(It prompts for credentials at install time, so the file itself contains
no secrets.)

The following files are generated on the server and contain real
credentials / numbers — **never commit them.**

- `~/.twilio_env` (Twilio credentials)
- `~/twilio_keepalive.py` (contains phone numbers)
- `~/keepalive.log` (run history)

Example `.gitignore`:

```
.twilio_env
*.log
twilio_venv/
twilio_keepalive.py
```
