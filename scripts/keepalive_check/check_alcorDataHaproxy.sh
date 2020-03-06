#!/bin/bash
# this script should be executable, e.g. chmod +x

# WARNING:
# 1. alcordata haproxy should have stats uri enabled, and have
#    check enabled for each server in backend
# 2. modify the following grep pattern for each backend

# Readme:
# 1. using haproxy statistics only to check if all alcordata cluster masters port
#    are unreachable is enough. If just some of them are unreachable, like one
#    master is down, haproxy will handle that, and it's no need to swap VIP.

cluster1Pattern="wnb1rds"
if [[ `curl -sf -u admin:alcordata "http://localhost:6391/stats;csv" | grep -c "${cluster1Pattern}L4OK"` -eq 0 ]]; then
    # all tcp port reachable check failed from current node
    exit 1
fi
