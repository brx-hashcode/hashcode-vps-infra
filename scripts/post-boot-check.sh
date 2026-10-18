#!/usr/bin/env bash
# Is the stack actually serving? Run by hashcode-stack.service after every
# boot, and safe to run by hand at any time.
#
# Exists because of 2026-10-18: after a reboot Traefik failed to bind :80 and
# exited, and every site was down for ~6 hours before anyone noticed. A
# restart policy brings containers back; this is what tells someone when one
# did not come back.
#
# Checks, in order:
#   1. traefik is running and :80 / :443 are bound
#   2. every container is up, and healthy where it has a healthcheck
#   3. every public Host(`...`) in the Traefik labels answers non-5xx
# then posts one summary to Slack (VPS_SLACK_ALERT_WEBHOOK in .env).
#
# Containers that are still starting get a few rounds to settle before they
# count as failures, so a slow boot is not reported as an outage.
#
#   CHECK_REASON="Manual check" scripts/post-boot-check.sh   # different title
#   NO_SLACK=1 scripts/post-boot-check.sh                    # print only
#
# Never prints the webhook: it is read into a variable and handed to curl as
# a config on stdin, so it is not on the command line either.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REASON="${CHECK_REASON:-Server rebooted}"
ATTEMPTS="${CHECK_ATTEMPTS:-6}"
WAIT_SECONDS="${CHECK_WAIT_SECONDS:-20}"
HOST_NAME="$(hostname)"

# ── Checks ───────────────────────────────────────────────────────────────────

check_traefik() {
  local state
  state="$(docker inspect -f '{{.State.Status}}' traefik 2>/dev/null || echo missing)"
  [[ "$state" == "running" ]] || echo "traefik is ${state}"
  for port in 80 443; do
    ss -tlnH "sport = :${port}" | grep -q . || echo "nothing listening on :${port}"
  done
}

# Not running, restarting, or unhealthy. "health: starting" is not a failure
# yet: the retry loop below gives it time.
check_containers() {
  docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}' |
    while IFS='|' read -r name state status; do
      if [[ "$state" != "running" ]]; then
        echo "${name}: ${status}"
      elif [[ "$status" == *"(unhealthy)"* ]]; then
        echo "${name}: unhealthy"
      fi
    done
}

public_hosts() {
  docker ps -q |
    xargs -r docker inspect -f '{{range $k, $v := .Config.Labels}}{{$v}}{{"\n"}}{{end}}' |
    grep -o 'Host(`[^`]*`)' |
    sed -E 's/^Host\(`(.*)`\)$/\1/' |
    sort -u
}

# 5xx or no answer at all (000) is a failure; a 401 behind basicauth or a 404
# on a bare API root means the route is up.
check_hosts() {
  local host code
  for host in $(public_hosts); do
    # A router for a name nobody published is a config problem, not an outage:
    # say which one it is.
    if ! getent ahosts "$host" >/dev/null; then
      echo "https://${host}/ → no DNS record"
      continue
    fi
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${host}/" || true)"
    if [[ -z "$code" || "$code" == "000" || "$code" -ge 500 ]]; then
      echo "https://${host}/ → ${code:-000}"
    fi
  done
}

run_checks() {
  check_traefik
  check_containers
  check_hosts
}

# ── Run, giving a slow boot time to settle ──────────────────────────────────

failures=""
for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
  failures="$(run_checks)"
  [[ -z "$failures" ]] && break
  ((attempt < ATTEMPTS)) && sleep "$WAIT_SECONDS"
done

container_count="$(docker ps -q | wc -l | tr -d ' ')"
host_count="$(public_hosts | wc -l | tr -d ' ')"

if [[ -z "$failures" ]]; then
  summary="✅ ${REASON} (${HOST_NAME}): all services OK — ${container_count} containers up, ${host_count} hosts answering."
  status=0
else
  summary="🚨 ${REASON} (${HOST_NAME}): problems after ${ATTEMPTS} checks:
$(sed 's/^/• /' <<<"$failures")"
  status=1
fi

echo "$summary"

# ── Slack ────────────────────────────────────────────────────────────────────

if [[ "${NO_SLACK:-0}" != "1" ]]; then
  webhook="$(grep '^VPS_SLACK_ALERT_WEBHOOK=' "${REPO_DIR}/.env" 2>/dev/null | head -1 | cut -d= -f2-)"
  if [[ -z "$webhook" ]]; then
    echo "VPS_SLACK_ALERT_WEBHOOK is not set in .env — no Slack message sent." >&2
  else
    payload="$(jq -n --arg text "$summary" '{text: $text}')"
    if ! printf 'url = "%s"\n' "$webhook" |
      curl -sS -o /dev/null --max-time 15 -X POST \
        -H 'Content-Type: application/json' --data "$payload" -K -; then
      echo "Slack post failed." >&2
    fi
  fi
  unset webhook
fi

exit "$status"
