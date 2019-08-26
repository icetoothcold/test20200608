#!/bin/bash

TYPE=$1
NAME=$2
STATE=$3

case $STATE in
    "MASTER")
        redisId=`/usr/bin/curl --unix-socket /var/run/docker.sock "http:/containers/redis/json" | python -mjson.tool | awk -F'"' '/"Id"/{print $4}'`
        harborDbId=`/usr/bin/curl --unix-socket /var/run/docker.sock "http:/containers/harbor-db/json" | python -mjson.tool | awk -F'"' '/"Id"/{print $4}'`
        nginxId=`/usr/bin/curl --unix-socket /var/run/docker.sock "http:/containers/nginx/json" | python -mjson.tool | awk -F'"' '/"Id"/{print $4}'`
        /usr/bin/curl --unix-socket /var/run/docker.sock -X POST "http:/containers/$redisId/restart"
        /usr/bin/curl --unix-socket /var/run/docker.sock -X POST "http:/containers/$harborDbId/restart"
        /usr/bin/curl --unix-socket /var/run/docker.sock -X POST "http:/containers/$nginxId/restart"
        exit 0
        ;;
    "BACKUP")
        nginxId=`/usr/bin/curl --unix-socket /var/run/docker.sock "http:/containers/nginx/json" | python -mjson.tool | awk -F'"' '/"Id"/{print $4}'`
        /usr/bin/curl --unix-socket /var/run/docker.sock -X POST "http:/containers/$nginxId/stop"
        exit 0
        ;;
    "FAULT")
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
