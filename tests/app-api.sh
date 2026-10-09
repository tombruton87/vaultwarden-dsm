# Vaultwarden's CGI checks (sourced by chassis/tests/test-api.sh).
expect "admintoken" 202 "$(post "$me" admintoken 'action=admintoken')"; request_is "admintoken request" "ACTION='admintoken'
BY='$me'"
expect "signups on" 202 "$(post "$me" signups 'action=signups&on=1')"; request_is "signups request" "ACTION='signups'
ON='1'
BY='$me'"
expect "signups bad" 400 "$(post "$me" signups 'action=signups&on=2')"
expect "invite good" 202 "$(post "$me" invite 'action=invite&email=a%40b.co')"; rm -f "$CHASSIS_VAR/request"
expect "invite bad" 400 "$(post "$me" invite 'action=invite&email=not-an-email')"
expect "remove2fa good" 202 "$(post "$me" remove2fa 'action=remove2fa&uuid=12345678-1234-1234-1234-123456789abc')"; rm -f "$CHASSIS_VAR/request"
expect "remove2fa bad" 400 "$(post "$me" remove2fa 'action=remove2fa&uuid=1')"
