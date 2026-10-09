    echo "SIGNUPS='$([ "${wizard_signups_closed:-false}" = true ] && echo 0 || echo 1)'"
    echo "TLS='$(if [ "${wizard_tls_self:-false}" = true ]; then echo self; elif [ "${wizard_tls_off:-false}" = true ]; then echo off; else echo dsm; fi)'"
