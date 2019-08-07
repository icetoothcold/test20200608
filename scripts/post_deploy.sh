skipFirstN=0
skipLastFrom=0
declare -a notSkip=()

rootPath="$(cd `dirname $0`; cd .. ; pwd)"
source $rootPath/scripts/utils.sh

post_deploy_check $1
if [[ $checkFailed -eq 1 ]]; then
    exit 1
fi
clusterName=$1
clusterFile=$rootPath/clusters/$1.yml
parse_cluster_file

hostsFile=$rootPath/kubespray/inventory/$clusterName/hosts.yml
# masterIPs is a string, not an array, but it's ok
masterIPs=`python3 -c "import yaml; all=yaml.safe_load(open('$hostsFile'))['all']; print(' '.join([all['hosts'][host]['ip'] for host in all['hosts'] if host in all['children']['kube-master']['hosts']]))"`

echo_task "install kubectl completion"
if [[ $skipped -ne 1 ]]; then
    ctlcmpl="install_kubectl_completion.sh"
    for ip in ${masterIPs[@]}; do
        ssh root@$ip "curl $pkgRepo/$ctlcmpl -o $ctlcmpl && bash $ctlcmpl && rm -f $ctlcmpl"
    done
fi

echo_task "push cluster infra charts"
if [[ $skipped -ne 1 ]]; then
    ts=`date +%s`
    tmpData=$rootPath/chrt_data.tmp$ts
    cat $clusterFile $rootPath/versions/common $rootPath/infra.yml >> $tmpData
    if [[ -z `awk '/all_vip_listeners/{print $2}' $tmpData` ]]; then
        sed -i "s/^all_vip_listeners:.*$/all_vip_listeners: \"${masterIPs[@]}\"/" $tmpData
    fi
    pushd $chartPath
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
fi

echo_task "add cluster infra helm repo"
if [[ $skipped -ne 1 ]]; then
    for ip in ${masterIPs[@]}; do
        ssh root@$ip "helm repo add infra $chartRepo/$clusterName/infra"
    done
fi

echo_task "install ingress/traefik"
if [[ $skipped -ne 1 ]]; then
    ahost=`echo $masterIPs | cut -d ' ' -f 1`
    ssh root@$ahost "helm repo update; helm del --purge ingress-tfk; helm install infra/traefik --name ingress-tfk --namespace kube-system"
fi

echo_task "install keepalived-vip"
if [[ $skipped -ne 1 ]]; then
    ahost=`echo $masterIPs | cut -d ' ' -f 1`
    ssh root@$ahost "helm repo update; helm del --purge kpvip; helm install infra/keepalived-vip --name kpvip --namespace kube-system"
fi
