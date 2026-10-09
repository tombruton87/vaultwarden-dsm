# Vaultwarden's steps for chassis/tests/e2e.sh (sourced; request/VAR/APP/PORT come from it).
app_e2e_answers() { printf "SIGNUPS='1'\nTLS='dsm'\n"; }   # dsm: no DSM certificate here, so the self-signed fallback is what gets tested
app_e2e_act() {
  local fail=0 tok jar code uuid
  log "vaultwarden"
  curl -sk -o /dev/null -w '  (alive: HTTP %{http_code})\n' "https://127.0.0.1:$PORT/alive"
  jq -e '.app.users | type == "array"' "$VAR/status.json" >/dev/null && echo "  ok   users list present ($(jq -r '.app.users | length' "$VAR/status.json") accounts), signups=$(jq -r .app.signups "$VAR/status.json")" || { echo "  FAIL status.app: $(jq -c '.app' "$VAR/status.json" | cut -c1-200)"; fail=1; }
  # The admin token the first start left, and whether it opens the admin page (argon2 hash in the container).
  tok=$(jq -r '.password // ""' "$VAR/secret.json" 2>/dev/null)
  [[ ${#tok} -ge 30 ]] && echo "  ok   a one-time admin token was left for the window" || { echo "  FAIL no admin token secret"; fail=1; }
  jar=$(mktemp); code=$(curl -sk -o /dev/null -c "$jar" -w '%{http_code}' --data-urlencode "token=$tok" "https://127.0.0.1:$PORT/admin"); grep -q VW_ADMIN "$jar" && echo "  ok   the token signs in to the admin page (HTTP $code)" || { echo "  FAIL admin sign-in with the token: HTTP $code"; fail=1; }
  code=$(curl -sk -o /dev/null -w '%{http_code}' --data-urlencode "token=wrong-token-xyz" "https://127.0.0.1:$PORT/admin"); [[ "$code" =~ ^(401|200|302)$ ]] && echo "  (wrong admin token: HTTP $code)"
  rm -f "$jar" "$VAR/secret.json"
  request "ACTION='invite'" "EMAIL='invited@example.com'" || fail=1
  uuid=$(jq -r '.app.users[] | select(.email == "invited@example.com") | .id' "$VAR/status.json")
  [[ -n "$uuid" ]] && echo "  ok   the invited account is listed ($uuid)" || { echo "  FAIL invited user not listed: $(jq -c '.app.users' "$VAR/status.json")"; fail=1; }
  if [[ -n "$uuid" ]]; then
    request "ACTION='remove2fa'" "USER_UUID='$uuid'" || fail=1
    request "ACTION='userdisable'" "USER_UUID='$uuid'" || fail=1
    jq -r --arg u "$uuid" '.app.users[] | select(.id == $u) | .enabled' "$VAR/status.json" | grep -q false && echo "  ok   disabled" || { echo "  FAIL not disabled: $(jq -c --arg u "$uuid" '.app.users[] | select(.id == $u)' "$VAR/status.json")"; fail=1; }
    request "ACTION='userenable'" "USER_UUID='$uuid'" || fail=1
    request "ACTION='userdelete'" "USER_UUID='$uuid'" || fail=1
    jq -e --arg u "$uuid" '.app.users | map(select(.id == $u)) | length == 0' "$VAR/status.json" >/dev/null && echo "  ok   deleted" || { echo "  FAIL still listed"; fail=1; }
  fi
  # HTTPS: dsm was asked for, there's no DSM certificate here, so self-signed is in use; off and self switch the proxy over.
  jq -e '.app.tls.mode == "dsm" and .app.tls.source == "self" and (.app.tls.cert.subject | test("Vaultwarden"))' "$VAR/status.json" >/dev/null && echo "  ok   HTTPS: dsm asked, self-signed in use ($(jq -r '.app.tls.cert.subject' "$VAR/status.json"))" || { echo "  FAIL tls status: $(jq -c '.app.tls' "$VAR/status.json")"; fail=1; }
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/alive")" == 400 ]] && echo "  ok   plain http is refused on the HTTPS port" || echo "  (plain http on the HTTPS port: HTTP $(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/alive"))"
  request "ACTION='settings'" "TLS='off'" || fail=1
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/alive")" == 200 ]] && echo "  ok   HTTPS off: plain http answers" || { echo "  FAIL plain http after TLS=off"; fail=1; }
  jq -e '.app.tls.mode == "off" and (.url | startswith("http://"))' "$VAR/status.json" >/dev/null && echo "  ok   address went back to http://" || { echo "  FAIL url after TLS=off: $(jq -r .url "$VAR/status.json")"; fail=1; }
  request "ACTION='settings'" "TLS='self'" || fail=1
  [[ "$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1:$PORT/alive")" == 200 ]] && echo "  ok   HTTPS self: https answers" || { echo "  FAIL https after TLS=self"; fail=1; }
  jq -e '.app.tls.source == "self" and (.url | startswith("https://"))' "$VAR/status.json" >/dev/null && echo "  ok   address is https:// again" || { echo "  FAIL url after TLS=self: $(jq -r .url "$VAR/status.json")"; fail=1; }
  before=$(jq -r '.app.tls.cert.expires' "$VAR/status.json"); request "ACTION='refreshcert'" || fail=1
  jq -e '.app.tls.cert.subject | test("Vaultwarden")' "$VAR/status.json" >/dev/null && echo "  ok   a new self-signed certificate (was: $before)" || { echo "  FAIL refreshcert"; fail=1; }
  request "ACTION='signups'" "ON='0'" || fail=1
  jq -r .app.signups "$VAR/status.json" | grep -q false && echo "  ok   sign-ups closed" || { echo "  FAIL signups still open"; fail=1; }
  request "ACTION='signups'" "ON='1'" || fail=1
  request "ACTION='smtptest'" "EMAIL='nobody@example.com'" >/dev/null && echo "  (a test email went — SMTP is configured here?)" || echo "  ok   test email refused without SMTP: $(jq -r '.last.message' "$VAR/status.json" | cut -c1-80)…"
  # A failed sign-in shows up in the activity report.
  curl -sk -o /dev/null -d 'grant_type=password&username=nobody@example.com&password=x&scope=api+offline_access&client_id=web&deviceType=10&deviceIdentifier=e2e&deviceName=e2e' "https://127.0.0.1:$PORT/identity/connect/token"
  for i in $(seq 1 20); do touch "$VAR/watching"; jq -e '.app.failed.last_day > 0' "$VAR/status.json" >/dev/null 2>&1 && break; sleep 4; done
  jq -e '.app.failed.last_day > 0' "$VAR/status.json" >/dev/null && echo "  ok   the failed sign-in is counted: $(jq -c '.app.failed.by_ip' "$VAR/status.json")" || { echo "  FAIL failed sign-in not counted: $(jq -c '.app.failed' "$VAR/status.json")"; fail=1; }
  request "ACTION='admintoken'" || fail=1
  tok=$(jq -r '.password // ""' "$VAR/secret.json" 2>/dev/null); jar=$(mktemp); curl -sk -o /dev/null -c "$jar" --data-urlencode "token=$tok" "https://127.0.0.1:$PORT/admin"; grep -q VW_ADMIN "$jar" && echo "  ok   the new admin token signs in" || { echo "  FAIL new token"; fail=1; }; rm -f "$jar" "$VAR/secret.json"
  (( fail == 0 )) && echo "  vaultwarden: all passed" || echo "  vaultwarden: something FAILED"; return $fail
}
