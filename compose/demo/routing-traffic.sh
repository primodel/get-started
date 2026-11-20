#!/usr/bin/env bash
# Routing demo traffic generator.
#
# Keeps the routing pages (Topology, Dashboard, Journeys, Acknowledgements, Dead letters) populated:
#   Flow A  EDIFACT INVOIC files -> SFTP /inbound/invoices, then POST /api/triggers/{id}/notify.
#           Mostly normal invoices, some >= 5000 (anomaly), some from an unknown supplier (anomaly),
#           and one malformed file (dead letter).
#   Flow B  payload files + ".done" markers -> SFTP /outbound/source, picked up by the poller and
#           fanned out to partner-x / partner-y.
#
# Needs: bash, curl, jq, and an OpenSSH `sftp` client. Talks to the stack over HTTP and the SFTP sidecar only.
#
# Usage: routing-traffic.sh [--once] [--count N] [--rate PER_MINUTE]
#   --once          one round of every kind (normal, large, unknown supplier, malformed, outbound), then exit
#   --count N       number of rounds to run (default 20)
#   --rate R        rounds per minute (default 6)
#
# Environment (defaults are the documented local demo values):
#   PRIMODEL_URL          http://localhost:8080
#   DEMO_USER / DEMO_PASSWORD   demo login used to look up the trigger id
#   DEMO_TRIGGER_KEY      API key of the "Invoice intake (SFTP)" trigger
#   SFTP_HOST / SFTP_PORT / SFTP_USER / SFTP_PASSWORD   SFTP sidecar as published to the host (port 2222 by default compose)
set -euo pipefail

PRIMODEL_URL="${PRIMODEL_URL:-http://localhost:8080}"
DEMO_USER="${DEMO_USER:-ada}"
DEMO_PASSWORD="${DEMO_PASSWORD:-lovelace}"
DEMO_TRIGGER_KEY="${DEMO_TRIGGER_KEY:-primodel-demo-trigger-key}"
SFTP_HOST="${SFTP_HOST:-localhost}"
SFTP_PORT="${SFTP_PORT:-2222}"
SFTP_USER="${SFTP_USER:-${SFTP_DEMO_USER:-demo}}"
SFTP_PASSWORD="${SFTP_PASSWORD:-${SFTP_DEMO_PASSWORD:-primodel-demo}}"

COUNT=20
RATE=6
ONCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --once) ONCE=1 ;;
    --count) COUNT="$2"; shift ;;
    --rate) RATE="$2"; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
[ "$ONCE" = 1 ] && COUNT=1
case "$COUNT$RATE" in *[!0-9]*) echo "--count and --rate must be positive integers" >&2; exit 2 ;; esac
[ "$RATE" -ge 1 ] || { echo "--rate must be >= 1" >&2; exit 2; }
SLEEP=$((60 / RATE))

for tool in curl jq sftp; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
JAR="$WORK/cookies"
RUN="$(date -u +%m%d%H%M%S)"

# ssh(1) asks for the password through SSH_ASKPASS; the helper only echoes it.
printf '#!/bin/sh\nprintf "%%s\\n" "$SFTP_PASSWORD"\n' > "$WORK/askpass.sh"
chmod +x "$WORK/askpass.sh"
export SFTP_PASSWORD

sftp_run() { # reads sftp commands on stdin
  SSH_ASKPASS="$WORK/askpass.sh" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-none}" \
    sftp -q -P "$SFTP_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o PreferredAuthentications=password -o LogLevel=ERROR "$SFTP_USER@$SFTP_HOST" >/dev/null
}

# ---- trigger id (looked up through the normal API, never hardcoded) ----------------------------------------
login_body="$(jq -nc --arg u "$DEMO_USER" --arg p "$DEMO_PASSWORD" '{username:$u,password:$p}')"
login_ok=0
for attempt in 1 2 3 4; do # login is rate-limited; back off briefly instead of failing
  curl -fsS -c "$JAR" -H 'Content-Type: application/json' -d "$login_body" "$PRIMODEL_URL/api/auth/login" >/dev/null 2>&1 \
    && { login_ok=1; break; }
  sleep $((attempt * 5))
done
[ "$login_ok" = 1 ] || { echo "login failed against $PRIMODEL_URL" >&2; exit 1; }
TRIGGER_ID="$(curl -fsS -b "$JAR" "$PRIMODEL_URL/api/triggers" \
  | jq -r '[.[] | select(.displayName=="Invoice intake (SFTP)")][0].triggerId // empty')"
[ -n "$TRIGGER_ID" ] || { echo "trigger 'Invoice intake (SFTP)' not found - is the routing demo seeded?" >&2; exit 1; }

# ---- EDIFACT generation (segment layout matches the seeded route's projections) -----------------------------
SUPPLIERS=(SUP-1001:SEK SUP-1002:SEK SUP-1003:EUR SUP-1004:EUR SUP-1005:USD)
SEQ=0

uuid() { local h; h="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"; echo "${h:0:8}-${h:8:4}-4${h:13:3}-a${h:17:3}-${h:20:12}"; }
rand() { echo $(( RANDOM % ($2 - $1 + 1) + $1 )); } # inclusive range

message() { # message <n> <invoice-no> <supplier> <currency> <amount> <yyyymmdd>
  printf "UNH+%s+INVOIC:D:96A:UN:EAN008'\r\nBGM+380+%s+9'\r\nDTM+137:%s:102'\r\nNAD+SU+%s'\r\nNAD+BY+PRIMODEL-HQ'\r\nCUX+2:%s:4'\r\nMOA+77:%s'\r\nUNT+7+%s'\r\n" \
    "$1" "$2" "$6" "$3" "$4" "$5" "$1"
}

invoice_file() { # invoice_file <path> <kind: normal|large|unknown> [messages]
  local path="$1" kind="$2" msgs="${3:-1}" body="" i s code cur amt day
  day="$(date -u +%Y%m%d)"
  for i in $(seq 1 "$msgs"); do
    SEQ=$((SEQ + 1))
    s="${SUPPLIERS[$(( (SEQ - 1) % ${#SUPPLIERS[@]} ))]}"; code="${s%%:*}"; cur="${s##*:}"
    case "$kind" in
      large)   amt="$(rand 5000 24000).$(rand 10 99)" ;;
      unknown) code="SUP-9999"; amt="$(rand 200 4500).$(rand 10 99)" ;;
      *)       amt="$(rand 80 4800).$(rand 10 99)" ;;
    esac
    body+="$(message "$i" "INV-$RUN-$SEQ" "$code" "$cur" "$amt" "$day")"$'\n'
  done
  printf "UNA:+.? '\r\nUNB+UNOC:3+%s:14+PRIMODEL-HQ:14+%s:%s+%s'\r\n%sUNZ+%s+%s'\r\n" \
    "$code" "$(date -u +%y%m%d)" "$(date -u +%H%M)" "$RUN$SEQ" "$(printf '%s' "$body" | tr -d '\n')" "$msgs" "$RUN$SEQ" > "$path"
}

malformed_file() { # a syntactically valid interchange whose amount is not a number (fails at the content router)
  printf "UNA:+.? '\r\nUNB+UNOC:3+SUP-1001:14+PRIMODEL-HQ:14+%s:0000+%s'\r\nUNH+1+INVOIC:D:96A:UN:EAN008'\r\nBGM+380+INV-%s-BAD+9'\r\nDTM+137:%s:102'\r\nNAD+SU+SUP-1001'\r\nCUX+2:SEK:4'\r\nMOA+77:NOT-A-NUMBER'\r\nUNT+6+1'\r\nUNZ+1+%s'\r\n" \
    "$(date -u +%y%m%d)" "$RUN" "$RUN" "$(date -u +%Y%m%d)" "$RUN" > "$1"
}

# ---- one round ---------------------------------------------------------------------------------------------
notify() { # notify <remote-path> <size>
  local body status
  body="$(jq -nc --arg id "$(uuid)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg p "${1#/}" --argjson s "$2" \
    '{eventId:$id,occurredAt:$at,location:{kind:"sftp",path:("/"+$p),size:$s}}')"
  status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -H "X-Api-Key: $DEMO_TRIGGER_KEY" -d "$body" "$PRIMODEL_URL/api/triggers/$TRIGGER_ID/notify" || echo 000)"
  echo "  notify $1 -> HTTP $status"; [ "$status" = 202 ] || echo "  request body: $body" >&2
}

round() { # round <n>
  local n="$1" kind name f cmds=""
  # Mix per round: 1 in 4 large, 1 in 6 unknown supplier, one malformed file on round 3 (and in --once).
  if   [ "$ONCE" = 1 ]; then kinds=(normal large unknown malformed)
  elif [ "$n" -eq 3 ];  then kinds=(malformed)
  elif [ $((n % 4)) -eq 0 ]; then kinds=(large)
  elif [ $((n % 6)) -eq 5 ]; then kinds=(unknown)
  else kinds=(normal); fi

  local names=()
  for kind in "${kinds[@]}"; do
    name="invoice-$RUN-$n-$kind.edi"; f="$WORK/$name"
    if [ "$kind" = malformed ]; then malformed_file "$f"; else invoice_file "$f" "$kind" "$(rand 1 2)"; fi
    cmds+="put $f /inbound/invoices/$name"$'\n'
    names+=("$name")
  done

  # Flow B: every other round (always in --once) drop a payload plus its .done marker.
  local out=""
  if [ "$ONCE" = 1 ] || [ $((n % 2)) -eq 0 ]; then
    out="partner-update-$RUN-$n.json"
    jq -nc --arg n "$out" --argjson i "$n" '{document:$n,sequence:$i,type:"price-list",items:[range(0;3)|{sku:("SKU-\(.+1)"),price:(100+.*7)}]}' > "$WORK/$out"
    printf "{}" > "$WORK/$out.done"
    cmds+="put $WORK/$out /outbound/source/$out"$'\n'"put $WORK/$out.done /outbound/source/$out.done"$'\n'
  fi

  printf '%s' "$cmds" | sftp_run || { echo "  SFTP upload failed (host $SFTP_HOST:$SFTP_PORT)" >&2; return 1; }
  echo "round $n: uploaded ${names[*]} ${out:+and $out(.done)}"
  for name in "${names[@]}"; do notify "/inbound/invoices/$name" "$(wc -c < "$WORK/$name" | tr -d ' ')"; done
}

echo "trigger $TRIGGER_ID | $COUNT round(s), $RATE/min | sftp $SFTP_USER@$SFTP_HOST:$SFTP_PORT"
for n in $(seq 1 "$COUNT"); do
  round "$n" || true
  [ "$n" -lt "$COUNT" ] && sleep "$SLEEP"
done
echo "done"
