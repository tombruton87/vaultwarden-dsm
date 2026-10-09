# Vaultwarden's actions, validated by the chassis CGI before they become a request file.
app_cgi_post() {   # action body → sets $lines, or error
  local a=$1 body=$2 on email uuid
  case "$a" in
    admintoken) lines="ACTION='admintoken'" ;;
    signups|invites|hints) on=$(param on "$body"); [[ "$on" =~ ^[01]$ ]] || error "400 Bad Request" "On or off."; lines="ACTION='$a'
ON='$on'" ;;
    invite|smtptest) email=$(decode "$(param email "$body")"); [[ "$email" =~ ^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || error "400 Bad Request" "An email address, like you@example.com."; lines="ACTION='$a'
EMAIL='$email'" ;;
    remove2fa|userdisable|userenable|userdelete) uuid=$(param uuid "$body"); [[ "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || error "400 Bad Request" "Pick a user."; lines="ACTION='$a'
USER_UUID='$uuid'" ;;
  esac
}
