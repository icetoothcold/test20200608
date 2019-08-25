rootPath="$(cd `dirname $0`; cd ..; pwd)"
source $rootPath/scripts/utils.sh

docker rm -f myrepo
docker run -d --name myrepo \
    -v $rootPath/rpms_and_files:/var/www/html \
    -v $rootPath/pypi3.6:/packages \
    -p $pkgRepoPort:8080 \
    -p $pypiPort:8090 \
    -e REPO_HOST=$pkgRepoHost:$pkgRepoPort \
    --restart 'always' \
    --health-cmd "curl --fail -s http://0.0.0.0:8080/private.repo 2>&1 1>/dev/null || exit 1" \
    --health-interval=2s \
    --health-timeout=2s \
    --health-retries=2 \
    --health-start-period=3s \
    $imgRepo/library/onecache
