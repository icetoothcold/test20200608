if [[ -z $1 ]]; then
    echo "No cluster name assigned"
    exit 1
fi
clusterName=$1

if [[ ${0##*/} == "dispatch_charts.sh" ]]; then
    rootPath="$(cd `dirname $0`; cd .. ; pwd)"
    source $rootPath/scripts/utils.sh
    hostsFile=$inventoryPath/$clusterName/hosts.yml
    # masterIPs is a string, not an array, but it's ok
    masterIPs=`python3 -c "import yaml; all=yaml.safe_load(open('$hostsFile'))['all']; print(' '.join([all['hosts'][host]['ip'] for host in all['hosts'] if host in all['children']['kube-master']['hosts']]))"`
fi
clusterFile=$clusterPath/$1.yml
kubeVersion=`cat $clusterFile | awk '/kubeVersion/{print $2}'`

ts=`date +%s`
tmpData=$rootPath/chrt_data.tmp$ts
cat $clusterFile $versionPath/common $versionPath/$kubeVersion $rootPath/infra.yml >> $tmpData
echo "clusterName: $clusterName" >> $tmpData
pushd $chartPath
# generate dexCA
for chr in `ls`; do
    if [[ -d $chr ]]; then
        cp -r $chr $chr.tmp
        jinja2 $chr.tmp/values.yaml $tmpData --format=yaml > $chr.tmp/values.yaml.tmp
        mv $chr.tmp/values.yaml.tmp $chr.tmp/values.yaml
        helm repo list | grep -q ${clusterName}Infra
        if [[ $? -ne 0 ]]; then
            helm repo add ${clusterName}Infra $chartRepo/$clusterName/infra
            if [[ $? -ne 0 ]]; then
                echo "failed to add repo ${clusterName}Infra"
                exit 1
            fi
        fi
        helm push $chr.tmp ${clusterName}Infra 2>/dev/null
        if [[ $? -ne 0 ]]; then
            chrVersion=`cat $chr/Chart.yaml | awk '/^version/{print $2}'`
            curl -X DELETE $chartRepo/api/$clusterName/infra/charts/$chr/$chrVersion
            helm push $chr.tmp ${clusterName}Infra
            if [[ $? -ne 0 ]]; then
                echo "failed to push $chr into private chart repo"
                exit 1
            fi
        fi
        rm -rf $chr.tmp
    fi
done
rm $tmpData
popd
