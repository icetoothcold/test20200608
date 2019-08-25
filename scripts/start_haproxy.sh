rootPath="$(cd `dirname $0`; cd ..; pwd)"
source $rootPath/scripts/utils.sh

docker rm -f haproxy
docker run -d --name haproxy \
    -v $templatePath/haproxy.repo.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \
    --restart 'always' \
    --network host \
    $imgRepo/library/haproxy
