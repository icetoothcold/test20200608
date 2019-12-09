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

# install helm if not exist
if [[ ! -f /usr/sbin/helm ]]; then
    curl $pkgRepo/helm/v2.14.3/linux/amd64/helm -o /usr/sbin/helm
    chmod u+x /usr/sbin/helm
fi

stableRepo="$chartRepo/local/infra"
repoPath=$chartRepo/$clusterName/infra
repoName="${clusterName}Infra"
repoApiPath=$chartRepo/api/$clusterName/infra
if [[ $harborWithChartmusuem == "true" ]]; then
    schema="http://"
    if [[ $imageRepoSecure == "true" ]]; then
        schema="https://"
    fi
    stableRepo=${schema}${imgRepo}/chartrepo/library
    repoPath=$stableRepo
    repoName="harbor-library"
    repoApiPath=${schema}${imgRepo}/api/chartrepo/library/charts
fi

# init helm if no repo exist
if [[ `helm repo list >/dev/null 2>/dev/null ; echo $?` -ne 0 ]] ; then
    helm init --client-only --stable-repo-url $stableRepo
fi

# add repo for cluster if not exist
if [[ `helm repo list | grep -c "^$repoName"` -eq 0 ]]; then
    helm repo add $repoName $repoPath
    if [[ $? -ne 0 ]]; then
        echo "failed to add repo $repoName"
        exit 1
    fi
fi

# install helm push plugin if not exist
if [[ `helm plugin list | grep -c push` -eq 0 ]]; then
    curl $pkgRepo/helm-push.tar -o $rootPath/helm-push.tar
    tar xf $rootPath/helm-push.tar -C $rootPath
    curl $pkgRepo/helm-push_install_plugin.sh -o $rootPath/helm-push/scripts/install_plugin.sh
    helm plugin install $rootPath/helm-push
    rm -f $rootPath/helm-push.tar
fi

ts=`date +%s`
tmpData=$rootPath/chart_data.tmp$ts
clusterFile=$clusterPath/${1}.yml
kubeVersion=`cat $clusterFile | awk '/kubeVersion/{print $2}'`
cat $clusterFile $versionPath/common $versionPath/$kubeVersion $rootPath/infra.yml >> $tmpData
echo "clusterName: $clusterName" >> $tmpData

pushd $chartPath > /dev/null
for _chart in `ls`; do
    if [[ -d $_chart ]]; then
        chart=${_chart}.tmp
        cp -rp $_chart $chart
        jinja2 $chart/values.yaml $tmpData --format=yaml > $chart/values.yaml.tmp
        mv $chart/values.yaml.tmp $chart/values.yaml
        pushOpts=""
        if [[ $harborWithChartmusuem == "true" ]]; then
            pushOpts="-u admin -p $harborAdminPw"
        fi
        helm push $pushOpts $chart $repoName 2>/dev/null
        if [[ $? -ne 0 ]]; then
            chartVersion=`cat $chart/Chart.yaml | awk '/^version/{print $2}'`
            if [[ $harborWithChartmusuem != "true" ]]; then
                curl -X DELETE $repoApiPath/charts/$_chart/$chartVersion
            else
                curl -X DELETE -u "admin:$harborAdminPw" $repoApiPath/$_chart
            fi
            helm push $pushOpts $chart $repoName 2>/dev/null
            if [[ $? -ne 0 ]]; then
                echo "failed to push $_chart into private chart repo"
                exit 1
            fi
        fi
        rm -rf $chart
    fi
done
rm $tmpData
popd > /dev/null

# to generate index
helm repo update
