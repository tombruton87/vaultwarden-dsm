# Vaultwarden's hooks for the chassis core (sourced by run-core.sh). The
# core gives: say, env_get/env_set, rand, compose, in_volume, cname, svc_up,
# leave_secret, notify, MSG, VAR, APP, LOG, PKG_NAME, PKG_TITLE.

VW=""; ADMIN_TOKEN=""; JAR="$VAR/.admin-cookies"

app_validate() {   # key value → 0 if the value has the key's shape
  case "$1" in
    SIGNUPS)   [[ "$2" =~ ^[01]$ ]] ;;
    TLS)       [[ "$2" =~ ^(dsm|self|off)$ ]] ;;
    EMAIL)     [[ "$2" =~ ^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] ;;
    USER_UUID) [[ "$2" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ;;
    *) return 1 ;;
  esac
}

# The admin page's token: a random secret, hashed with argon2id for the
# container (what `docker inspect` shows is the hash), the plain one kept in
# .env (root only) for the window's own admin calls, and shown once.
hash_token() {   # plain → PHC string, $ doubled for compose's .env
  printf '%s' "$1" | argon2 "$(rand 16)" -e -id -k 65540 -t 3 -p 4 | sed 's/\$/$$/g'
}
new_admin_token() {
  local tok; tok=$(rand 40)
  env_set ADMIN_TOKEN "$tok"; env_set ADMIN_TOKEN_HASH "$(hash_token "$tok")"   # unquoted: compose turns $$ back into $
  ADMIN_TOKEN=$tok; rm -f "$JAR"
}
app_first_env() {
  env_set VW_IMAGE vaultwarden/server:latest; env_set PROXY_IMAGE nginx:stable-alpine
  env_set TLS "${TLS:-dsm}"
  [[ "${TLS:-dsm}" != off ]] && env_set APP_URL "https://$(env_get LAN_IP):$(env_get HTTP_PORT)"   # the Bitwarden apps need HTTPS
  env_set SIGNUPS_ALLOWED "$([[ "${SIGNUPS:-1}" == 0 ]] && echo false || echo true)"
  env_set INVITATIONS_ALLOWED true; env_set SHOW_PASSWORD_HINT false
  new_admin_token
  leave_secret "the admin page ($(env_get APP_URL)/admin)" "$ADMIN_TOKEN" admin
  say "first start: an admin token was made; it's shown once in the window"
}
app_load_env() { ADMIN_TOKEN=$(env_get ADMIN_TOKEN); set_vw; }
set_vw() { VW="$([[ "$(env_get TLS)" == off ]] && echo http || echo https)://127.0.0.1:$(env_get HTTP_PORT)"; }   # -k below: the certificate may be self-signed
app_health() { [[ "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$VW/alive" 2>/dev/null)" == 200 ]]; }
app_version() { curl -sk --max-time 5 "$VW/api/config" 2>/dev/null | jq -r '.version // ""' 2>/dev/null | tr -cd '0-9A-Za-z.-' | head -c 30; }

# The admin API, behind the token: sign in once per cookie file, retry on 401.
admin_login() { rm -f "$JAR"; curl -sk -o /dev/null -c "$JAR" --max-time 10 --data-urlencode "token=$ADMIN_TOKEN" "$VW/admin" 2>/dev/null; [[ -s "$JAR" ]] && grep -q VW_ADMIN "$JAR"; }
admin_call() {   # method path [json body] → body on stdout, HTTP code in ADMIN_CODE
  local m=$1 p=$2 body=${3:-} out
  [[ -s "$JAR" ]] || admin_login || { ADMIN_CODE=0; return 1; }
  out=$(curl -sk --max-time 20 -b "$JAR" -X "$m" -H 'Accept: application/json' -H 'Content-Type: application/json' ${body:+--data "$body"} -w '\n%{http_code}' "$VW/admin$p" 2>/dev/null)
  ADMIN_CODE=${out##*$'\n'}; out=${out%$'\n'*}
  if [[ "$ADMIN_CODE" == 401 ]]; then admin_login && { out=$(curl -sk --max-time 20 -b "$JAR" -X "$m" -H 'Accept: application/json' -H 'Content-Type: application/json' ${body:+--data "$body"} -w '\n%{http_code}' "$VW/admin$p" 2>/dev/null); ADMIN_CODE=${out##*$'\n'}; out=${out%$'\n'*}; }; fi
  printf '%s' "$out"; [[ "$ADMIN_CODE" =~ ^2 ]]
}
users_json() {
  svc_up server || { echo "[]"; return 0; }
  admin_call GET /users 2>/dev/null | jq -c 'if type == "array" then map({id: .id, email: .email, name: (.name // ""), enabled: (.userEnabled != false and .user_enabled != false), created: (.createdAt // .created_at // ""), last_active: (.lastActive // .last_active // ""), twofa: (.twoFactorEnabled == true), ciphers: (.cipher_count // 0), attachments: (.attachment_count // 0), attachment_size: (.attachment_size // ""), status: (._status // 0)}) else [] end' 2>/dev/null || echo "[]"
}
# ---------------------------------------------------------------- HTTPS
# nginx (the proxy service) fronts Vaultwarden. TLS=dsm: DSM's system-default
# certificate (Control Panel → Security → Certificate), read from the NAS and
# refreshed daily so renewals follow; TLS=self: a self-signed one made here;
# TLS=off: plain HTTP for DSM's reverse proxy. Config and certificate live in
# the vaultwarden_proxy volume; TLS_SOURCE in .env says what's really in use.
dsm_cert() {   # → tar (fullchain.pem privkey.pem) of DSM's system-default certificate on stdout; 1 when there is none here
  docker run --rm -v /usr:/host-usr:ro --entrypoint sh "$PKG_NAME-setup:local" -c \
    'd=/host-usr/syno/etc/certificate/system/default; [ -s "$d/fullchain.pem" ] && [ -s "$d/privkey.pem" ] && tar -C "$d" -chf - fullchain.pem privkey.pem' 2>/dev/null
}
self_cert() {   # → tar of a fresh self-signed certificate for this address (ten years) on stdout
  local d host ip san; d=$(mktemp -d); host=$(sed -E 's#^https?://##; s#[:/].*$##' <<< "$(env_get APP_URL)"); ip=$(env_get LAN_IP)
  san="IP:$ip"; if [[ "$host" =~ ^[0-9.]+$ ]]; then [[ "$host" != "$ip" ]] && san="$san,IP:$host"; else san="$san,DNS:$host"; fi
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$d/privkey.pem" -out "$d/fullchain.pem" -subj "/CN=Vaultwarden on ${host:-$ip}" \
    -addext "subjectAltName=$san" -addext "basicConstraints=CA:FALSE" -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1 || { rm -rf "$d"; return 1; }
  tar -C "$d" -cf - fullchain.pem privkey.pem; rm -rf "$d"
}
proxy_conf() {   # mode → nginx's server block on stdout (the volume is /etc/nginx/conf.d in the proxy)
  cat <<EOF
# Written by the Vaultwarden package; edits are overwritten on the next start.
map \$http_x_real_ip \$vw_client { "" \$remote_addr; default \$http_x_real_ip; }
map \$http_upgrade \$vw_conn { default upgrade; "" close; }
server {
EOF
  if [[ "$1" == off ]]; then echo "  listen 8080;"; else cat <<EOF
  listen 8080 ssl;
  http2 on;
  ssl_certificate /etc/nginx/conf.d/tls/fullchain.pem;
  ssl_certificate_key /etc/nginx/conf.d/tls/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_session_cache shared:vw:5m;
EOF
  fi
  cat <<'EOF'
  client_max_body_size 525M;
  resolver 127.0.0.11 valid=10s;
  location / {
    set $vw_up http://server:80;
    proxy_pass $vw_up;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $vw_conn;
    proxy_set_header X-Real-IP $vw_client;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 300s;
  }
}
EOF
}
store_cert() {   # tar file, source → into the volume
  in_volume proxy rw -- "mkdir -p /vol/tls && tar -C /vol/tls -xf - && chmod 600 /vol/tls/privkey.pem && echo $2 > /vol/tls/source" < "$1" 2>>"$LOG"
}
cert_info() {   # → JSON about the certificate in the volume, kept in $VAR/cert.json for the window
  local pem subj iss exp days sans
  pem=$(in_volume proxy ro -- 'cat /vol/tls/fullchain.pem 2>/dev/null' </dev/null 2>/dev/null)
  if [[ -z "$pem" ]]; then echo null > "$VAR/cert.json"; return 0; fi
  subj=$(openssl x509 -noout -subject -nameopt RFC2253 <<< "$pem" 2>/dev/null | sed 's/^subject=//'); iss=$(openssl x509 -noout -issuer -nameopt RFC2253 <<< "$pem" 2>/dev/null | sed 's/^issuer=//')
  exp=$(openssl x509 -noout -enddate <<< "$pem" 2>/dev/null | sed 's/^notAfter=//'); days=$(( ($(date -d "$exp" +%s 2>/dev/null || echo 0) - $(now)) / 86400 ))
  sans=$(openssl x509 -noout -ext subjectAltName <<< "$pem" 2>/dev/null | tail -n +2 | tr -d ' \n' | head -c 300)
  jq -n -c --arg s "$subj" --arg i "$iss" --arg e "$exp" --argjson d "$days" --arg san "$sans" --arg src "$(env_get TLS_SOURCE)" \
    '{subject: $s, issuer: $i, expires: $e, days_left: $d, names: $san, self_signed: ($s == $i), source: $src}' > "$VAR/cert.json.tmp" && mv "$VAR/cert.json.tmp" "$VAR/cert.json"
}
fix_url_scheme() {   # the address's scheme follows the HTTPS mode → 0 when it changed
  local url; url=$(env_get APP_URL)
  if [[ "$(env_get TLS)" != off && "$url" == http://* ]]; then env_set APP_URL "https://${url#http://}"; say "the address is https://${url#http://} — Vaultwarden serves HTTPS itself"
  elif [[ "$(env_get TLS)" == off && "$(env_get SSL_PROXY)" == 0 && "$url" == https://* ]]; then env_set APP_URL "http://${url#https://}"; say "the address is http://${url#https://} — HTTPS is off and nothing in front provides it"
  else return 1; fi
}
setup_proxy() {   # the proxy's config and certificate for the chosen mode (every start, and when the setting changes)
  local mode source tarf="$VAR/.cert.tar"
  [[ -n "$(env_get TLS)" ]] || { env_set TLS dsm; say "upgrade from 1.0: HTTPS with DSM's certificate is on now (the Site address tab can change it)"; }
  fix_url_scheme || true
  mode=$(env_get TLS); source=$mode; : > "$tarf"
  if [[ "$mode" == dsm ]]; then
    if ! { dsm_cert > "$tarf" && [[ -s "$tarf" ]]; }; then
      [[ "$(env_get TLS_SOURCE)" == self ]] || say "DSM's certificate wasn't found here (no system-default certificate, or not a Synology) — a self-signed one is used instead"
      source=self; : > "$tarf"
    fi
  fi
  if [[ "$source" == self ]]; then   # keep the one already there: the browser's exception for it survives restarts
    if ! in_volume proxy ro -- '[ "$(cat /vol/tls/source 2>/dev/null)" = self ] && [ -s /vol/tls/privkey.pem ]' </dev/null 2>/dev/null; then
      self_cert > "$tarf" && [[ -s "$tarf" ]] || { MSG="Couldn't make a self-signed certificate — see the log."; rm -f "$tarf"; return 1; }
      say "a self-signed certificate was made for $(env_get APP_URL)"
    fi
  fi
  if [[ "$mode" != off && -s "$tarf" ]]; then store_cert "$tarf" "$source" || { MSG="The certificate couldn't be stored for the proxy — see the log."; rm -f "$tarf"; return 1; }; fi
  rm -f "$tarf"
  proxy_conf "$mode" | in_volume proxy rw -- 'cat > /vol/vaultwarden.conf.tmp && mv /vol/vaultwarden.conf.tmp /vol/vaultwarden.conf' 2>>"$LOG" || { MSG="The proxy's config couldn't be written — see the log."; return 1; }
  env_set TLS_SOURCE "$([[ "$mode" == off ]] && echo off || echo "$source")"; cert_info; set_vw
}
reload_proxy() { svc_up proxy && { docker exec "$(cname proxy)" nginx -s reload >> "$LOG" 2>&1 || true; }; true; }
refresh_dsm_cert() {   # → 0 and "changed"/"same"/"none" in CERT_REFRESH
  local tarf="$VAR/.cert.tar" new old; CERT_REFRESH=none
  [[ "$(env_get TLS)" == dsm ]] || return 0
  dsm_cert > "$tarf" && [[ -s "$tarf" ]] || { rm -f "$tarf"; return 0; }
  new=$(tar -xOf "$tarf" fullchain.pem | sha256sum | cut -c1-16); old=$(in_volume proxy ro -- 'sha256sum /vol/tls/fullchain.pem 2>/dev/null' </dev/null 2>/dev/null | cut -c1-16)
  if [[ "$new" != "$old" ]]; then
    store_cert "$tarf" dsm && { env_set TLS_SOURCE dsm; cert_info; reload_proxy; CERT_REFRESH=changed; say "DSM's certificate changed (renewed, or chosen anew) — the HTTPS proxy picked it up"; }
  else CERT_REFRESH=same; fi
  rm -f "$tarf"; return 0
}
app_before_up() { setup_proxy || say "✗ the proxy couldn't be set up: $MSG"; }
app_settings() {   # TLS from the request; the address's scheme follows the mode
  local changed=0
  [[ -n "${TLS:-}" ]] && { env_set TLS "$TLS"; changed=1; }
  fix_url_scheme && changed=1
  setup_proxy || return 1
  reload_proxy; (( changed ))
}
app_tick() { fresh "$VAR/.cert-check" 86400 && return 0; touch "$VAR/.cert-check"; refresh_dsm_cert; }

# Failed sign-ins, from Vaultwarden's own log lines ("Username or password is incorrect. Try again. IP: 1.2.3.4. Username: x").
# The container's log dies with the container (a restart, a new admin token), so the lines are kept in a file on the
# share for seven days. Vaultwarden stamps lines in its own time zone; the cut-offs are made in that zone too.
FAILED_STORE=$APP/failed-logins.tsv
vw_date() { TZ="$(env_get TZ)" date -d "$1" '+%F %T'; }
harvest_failed() {   # merge the container's log into the store → lines "ip<TAB>user<TAB>time"
  local cut; cut=$(vw_date '7 days ago')
  { [[ -f "$FAILED_STORE" ]] && cat "$FAILED_STORE"
    docker logs --since 168h "$(cname server)" 2>&1 | grep -aE 'Username or password is incorrect|Invalid admin token|Invalid TOTP|Locked out|Too many login' \
      | sed -E 's/^\[([^]]*)\].*IP: ([0-9a-fA-F.:]*[0-9a-fA-F])\.? *(Username: ([^ ]*[^ .]))?.*$/\2\t\4\t\1/; t; s/^\[([^]]*)\].*$/?\t\t\1/' || true; } 2>/dev/null \
    | awk -F'\t' -v cut="$cut" 'NF == 3 && $3 >= cut' | sort -t$'\t' -k3,3 -u | tail -n 5000 > "$FAILED_STORE.tmp" 2>/dev/null && mv "$FAILED_STORE.tmp" "$FAILED_STORE"
  return 0
}
failed_logins() {   # 1h | 24h | 7d → the stored lines since then
  local cut; case "$1" in 1h) cut=$(vw_date '1 hour ago') ;; 24h) cut=$(vw_date '1 day ago') ;; *) cut=$(vw_date '7 days ago') ;; esac
  [[ -f "$FAILED_STORE" ]] && awk -F'\t' -v cut="$cut" '$3 >= cut' "$FAILED_STORE" | sort -t$'\t' -k3,3r | head -n 500
  return 0   # nothing stored is not a failure
}
app_status() {
  local users failed_h failed_d byip smtp
  users=$(users_json); harvest_failed
  failed_h=$(failed_logins 1h | wc -l | tr -cd '0-9'); failed_d=$(failed_logins 24h | wc -l | tr -cd '0-9')
  byip=$(failed_logins 24h | cut -f1 | sort | uniq -c | sort -rn | head -10 | awk '{print $2 "\t" $1}' | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {ip: .[0], count: (.[1] | tonumber? // 0)})' 2>/dev/null || echo "[]")
  (( ${failed_h:-0} >= 20 )) && notify bruteforce 6 "$failed_h"
  smtp=$(admin_call GET /diagnostics/config 2>/dev/null | jq -r '[.. | objects | select(has("smtp_host")) | .smtp_host] | first // ""' 2>/dev/null | head -c 120)
  [[ -s "$VAR/cert.json" ]] || cert_info
  jq -n -c --argjson users "$users" --argjson failed_h "${failed_h:-0}" --argjson failed_d "${failed_d:-0}" --argjson byip "$byip" --arg smtp "$smtp" \
    --arg tls "$(env_get TLS)" --arg tls_source "$(env_get TLS_SOURCE)" --argjson cert "$(cat "$VAR/cert.json" 2>/dev/null || echo null)" \
    --arg signups "$(env_get SIGNUPS_ALLOWED)" --arg invites "$(env_get INVITATIONS_ALLOWED)" --arg hints "$(env_get SHOW_PASSWORD_HINT)" --arg admin_url "$(env_get APP_URL)/admin" \
    '{users: $users, failed: {last_hour: $failed_h, last_day: $failed_d, by_ip: $byip}, smtp_host: $smtp, signups: ($signups == "true"), invites: ($invites == "true"), hints: ($hints == "true"), admin_url: $admin_url, tls: {mode: $tls, source: $tls_source, cert: $cert}}'
}
app_logs() { failed_logins 7d | awk -F'\t' '{printf "%s  %-16s %s\n", $3, $1, $2}' > "$VAR/logs/failed.log.tmp" 2>/dev/null; for_window "$VAR/logs/failed.log"; }

# Backups: a consistent copy of the SQLite database (sqlite3's .backup, from
# the setup image), then everything else in the volume except the live
# database files, the icon cache and temporary files.
app_backup() {   # dir
  in_volume data ro -- 'sqlite3 /vol/db.sqlite3 ".backup /tmp/db.sqlite3" && cat /tmp/db.sqlite3' > "$1/db.sqlite3" 2>>"$LOG" </dev/null && [[ -s "$1/db.sqlite3" ]] || { say "✗ the database copy didn't finish"; return 1; }
  in_volume data ro -- 'tar -C /vol -czf - --exclude=./db.sqlite3 --exclude="./db.sqlite3-*" --exclude=./icon_cache --exclude=./tmp .' > "$1/files.tar.gz" 2>>"$LOG" </dev/null && tar -tzf "$1/files.tar.gz" >/dev/null 2>&1 || { say "✗ the files didn't tar"; return 1; }
}
app_restore() {   # dir (containers are stopped)
  [[ -s "$1/db.sqlite3" && -f "$1/files.tar.gz" ]] || { MSG="That backup has no database copy or files."; return 1; }
  in_volume data rw -- 'find /vol -mindepth 1 -delete' </dev/null 2>>"$LOG" || { MSG="The data volume couldn't be emptied."; return 1; }
  in_volume data rw -- 'cat > /vol/db.sqlite3' < "$1/db.sqlite3" 2>>"$LOG" || { MSG="The database didn't copy back."; return 1; }
  in_volume data rw -- 'tar -C /vol -xzf -' < "$1/files.tar.gz" 2>>"$LOG" || { MSG="The files didn't unpack."; return 1; }
}
app_storage() {
  in_volume data ro -- 'cd /vol && for d in attachments sends icon_cache db.sqlite3; do [ -e "$d" ] && printf "%s\t%s\n" "$d" "$(du -sm "$d" 2>/dev/null | cut -f1)"; done' </dev/null 2>/dev/null \
    | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] | tonumber? // 0)}) | from_entries' 2>/dev/null || echo "{}"
}
app_report() {
  echo "== Vaultwarden settings (admin page, secrets dropped)"; admin_call GET /diagnostics/config 2>/dev/null | jq 'walk(if type == "object" then with_entries(select(.key | test("token|password|secret|key"; "i") | not)) else . end)' 2>/dev/null | head -n 120
  echo; echo "== HTTPS"; echo "mode $(env_get TLS), in use: $(env_get TLS_SOURCE)"; jq -c 'del(.names)' "$VAR/cert.json" 2>/dev/null
  echo; echo "== proxy config"; in_volume proxy ro -- 'cat /vol/vaultwarden.conf' </dev/null 2>/dev/null | grep -vE '^\s*$' | head -n 40
  echo; echo "== failed sign-ins, last 7 days"; failed_logins 7d | awk -F'\t' '{printf "%s  %-16s %s\n", $3, $1, $2}' | tail -n 50
}

restart_server() { compose up -d --remove-orphans >> "$LOG" 2>&1 && wait_ready 300; }
app_act() {   # action (request vars are set)
  case "$1" in
    admintoken)
      new_admin_token; say "a new admin token was made"
      restart_server || { MSG="The token was changed but Vaultwarden hasn't come back — see the log."; return 1; }
      leave_secret "the admin page ($(env_get APP_URL)/admin)" "$ADMIN_TOKEN" admin; MSG="A new admin token is ready — it's shown once, below." ;;
    signups)  env_set SIGNUPS_ALLOWED "$([[ "${ON:-0}" == 1 ]] && echo true || echo false)"; restart_server || { MSG="Vaultwarden didn't come back after the change — see the log."; return 1; }; MSG="Sign-ups are $([[ "${ON:-0}" == 1 ]] && echo "open: anyone who can reach Vaultwarden can create an account" || echo "closed: only invited people can join")." ;;
    invites)  env_set INVITATIONS_ALLOWED "$([[ "${ON:-0}" == 1 ]] && echo true || echo false)"; restart_server || { MSG="Vaultwarden didn't come back after the change — see the log."; return 1; }; MSG="Invitations are $([[ "${ON:-0}" == 1 ]] && echo on || echo off)." ;;
    hints)    env_set SHOW_PASSWORD_HINT "$([[ "${ON:-0}" == 1 ]] && echo true || echo false)"; restart_server || { MSG="Vaultwarden didn't come back after the change — see the log."; return 1; }; MSG="Password hints are $([[ "${ON:-0}" == 1 ]] && echo "shown on the sign-in page (not recommended)" || echo "only sent by email")." ;;
    invite)   local out; out=$(admin_call POST /invite "{\"email\":$(json "${EMAIL:-}")}") && MSG="$EMAIL was invited; they'll get an email if SMTP is set up, and can otherwise sign up with that address while sign-ups are open." || { MSG="Vaultwarden didn't invite $EMAIL (HTTP $ADMIN_CODE): $(head -c 200 <<< "$out")"; return 1; } ;;
    remove2fa) admin_call POST "/users/${USER_UUID:-}/remove-2fa" >/dev/null && MSG="Two-factor sign-in was removed for that account; they can sign in with just their master password and set 2FA up again." || { MSG="Vaultwarden didn't remove 2FA (HTTP $ADMIN_CODE)."; return 1; } ;;
    userdisable) admin_call POST "/users/${USER_UUID:-}/disable" >/dev/null && { admin_call POST "/users/${USER_UUID:-}/deauth" >/dev/null || true; MSG="The account is disabled and signed out everywhere."; } || { MSG="Vaultwarden didn't disable the account (HTTP $ADMIN_CODE)."; return 1; } ;;
    userenable)  admin_call POST "/users/${USER_UUID:-}/enable" >/dev/null && MSG="The account can sign in again." || { MSG="Vaultwarden didn't enable the account (HTTP $ADMIN_CODE)."; return 1; } ;;
    userdelete)  admin_call POST "/users/${USER_UUID:-}/delete" >/dev/null && MSG="The account and its vault were deleted." || { MSG="Vaultwarden didn't delete the account (HTTP $ADMIN_CODE)."; return 1; } ;;
    refreshcert)
      case "$(env_get TLS)" in
        dsm) rm -f "$VAR/.cert-check"; refresh_dsm_cert
             case "$CERT_REFRESH" in changed) MSG="DSM's certificate was read again and the proxy reloaded with it." ;; same) MSG="DSM's certificate hasn't changed; the proxy already has it." ;; *) MSG="DSM's certificate wasn't found on this system — see the log."; return 1 ;; esac ;;
        self) in_volume proxy rw -- 'rm -f /vol/tls/source' </dev/null 2>/dev/null; setup_proxy || return 1; reload_proxy; MSG="A new self-signed certificate was made; browsers will ask once more." ;;
        *) MSG="HTTPS is off here — there's no certificate to refresh."; return 1 ;;
      esac ;;
    smtptest) local r; r=$(admin_call POST /test/smtp "{\"email\":$(json "${EMAIL:-}")}") && MSG="A test email went to $EMAIL through Vaultwarden's SMTP settings." || { MSG="The test email didn't go (HTTP $ADMIN_CODE): $(head -c 300 <<< "$r" | tr -d '\n')"; return 1; } ;;
    *) MSG="Unknown request."; return 1 ;;
  esac
}
