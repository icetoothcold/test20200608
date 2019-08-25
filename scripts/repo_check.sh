# check if haproxy is healthy
# harbor
curl -sf --retry 3 --retry-delay 1 --retry-max-time 10 localhost:80
if [[ $? -ne 0 ]]; then
    exit 1
fi
# ldap
curl -sf --retry 3 --retry-delay 1 --retry-max-time 10 curl ldap://localhost:389
if [[ $? -ne 0 ]]; then
    exit 1
fi
exit 0
