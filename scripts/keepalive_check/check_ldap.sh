#!/bin/bash
# this script should be executable, e.g. chmod +x
# check ldap is reachable on its host
curl -sf --retry 3 --retry-delay 1 --retry-max-time 10 ldap://localhost:389
if [[ $? -ne 0 ]]; then
    exit 1
fi
exit 0
