rootPath="$(cd `dirname $0`; cd ..; pwd)"
source $rootPath/scripts/utils.sh
dataPath=$rootPath/chartmuseum_data
if [[ ! -d $dataPath ]]; then
    mkdir $rootPath/chartmuseum_data
fi
if [[ `ls -l $rootPath | grep "$dataPath$" | awk '{print $3":"$4}'` != "1000:1000" ]]; then
    chown 1000:1000 $dataPath
fi

docker rm -f chartmuseum
docker run -d \
  -p $chartRepoPort:8080 \
  -e DEBUG=1 \
  -e STORAGE=local \
  -e STORAGE_LOCAL_ROOTDIR=/charts \
  -e DEPTH=2 \
  -v $dataPath:/charts \
  --name chartmuseum \
  --restart 'always' \
  -u 1000:1000 \
  chartmuseum/chartmuseum:latest
