rootPath="$(cd `dirname $0`; cd ..; pwd)"
source $rootPath/scripts/utils.sh

docker rm -f haproxy
# haproxy will be started after harbor re-configured to listen on harborHABackendPort
# otherwise, haproxy will start failed for port conflict
docker run -d --name haproxy \
    -v $templatePath/haproxy.repo.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \
    --restart 'always' \
    --network host \
    $imgRepo:$harborHABackendPort/library/haproxy
