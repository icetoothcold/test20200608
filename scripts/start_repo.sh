path="$(cd `dirname $0`; cd ..; pwd)"
pkgRepoHost=`cat $path/infra.yml | awk -F'"' '/pkgRepo/{print $2}'| cut -d '/' -f 3`
pkgRepoPort=`echo $pkgRepoHost | cut -d ':' -f 2`
pypiPort=`cat $path/infra.yml | awk '/pypiPort/{print $2}'`

docker rm -f myrepo
docker run -d --name myrepo \
    -v $path/rpms_and_files:/var/www/html \
    -v $path/pypi3.6:/packages \
    -p $pkgRepoPort:8080 \
    -p $pypiPort:8090 \
    -e REPO_HOST=$pkgRepoHost \
    --restart 'always' \
    --health-cmd "curl --fail -s http://0.0.0.0:8080/private.repo 2>&1 1>/dev/null || exit 1" \
    --health-interval=2s \
    --health-timeout=2s \
    --health-retries=2 \
    --health-start-period=3s \
    onecache
