#!/bin/bash
# this script should be executable, e.g. chmod +x
curl -sf --retry 3 --retry-delay 1 --retry-max-time 10 localhost:8888
if [[ $? -ne 0 ]]; then
    exit 1
fi
exit 0
