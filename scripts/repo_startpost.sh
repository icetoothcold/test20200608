path="$(cd `dirname $0`; cd ..; pwd)"

docker ps -a | grep goharbor | grep -q "Exited"
if [[ $? -eq 0 ]]; then
    pushd $path/harbor
    docker-compose down
    docker-compose up -d
    popd
fi
docker ps -a | grep myrepo | grep -q "unhealthy"
if [[ $? -eq 0 ]]; then
    bash $path/scripts/start_repo.sh
fi
bash $path/scripts/start_chartmuseum.sh
