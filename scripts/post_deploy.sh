skipFirstN=0
skipLastFrom=0
notSkip=()

rootPath="$(cd `dirname $0`; cd .. ; pwd)"
source $rootPath/scripts/utils.sh

post_deploy_check $1
if [[ $checkFailed -eq 1 ]]; then
    exit 1
fi
clusterName=$1
clusterFile=$clusterPath/$1.yml
parse_cluster_file

# masterIPs is a string, not an array, but it's ok for for-loop
masterIPs=`get_master_ips_string $clusterName`
masterA=`echo $masterIPs | cut -d ' ' -f 1`

masterKubeletCM="master-kubelet-cm"
infraKubeletCM="infra-kubelet-cm"
nodeKubeletCM="node-kubelet-cm"
bootstrapKubeletCMFile="/etc/kubernetes/my-kubelet-config.yaml"

kubeNodeNames=`get_node_nodename_strings $clusterName`
kubeInfraNames=`get_infra_nodename_strings $clusterName`

echo_task "label node for different purposes"
# TODO: If overwrite node's label which role=master
if [[ $skipped -ne 1 ]]; then
    for node in ${kubeNodeNames[@]}; do
        ssh root@$masterA "kubectl label node $node node-role.kubernetes.io/node=  --overwrite"
    done
    for infra in ${kubeNodeNames[@]}; do
        ssh root@$masterA "kubectl label node $infra node-role.kubernetes.io/infra=  --overwrite"
    done
fi

echo_task "config kubelet dynamic configuration"
if [[ $skipped -ne 1 ]]; then
    ssh root@$masterA "kubectl -n kube-system delete cm $masterKubeletCM; \
                       kubectl -n kube-system delete cm $infraKubeletCM; \
                       kubectl -n kube-system delete cm $nodeKubeletCM; \
                       cp -f /etc/kubernetes/kubelet-config.yaml $bootstrapKubeletCMFile; \
                       sed -i 's/^address:.*/address: 0.0.0.0/g' $bootstrapKubeletCMFile; \
                       kubectl -n kube-system create cm $masterKubeletCM --from-file=kubelet=$bootstrapKubeletCMFile; \
                       kubectl -n kube-system create cm $infraKubeletCM --from-file=kubelet=$bootstrapKubeletCMFile; \
                       kubectl -n kube-system create cm $nodeKubeletCM --from-file=kubelet=$bootstrapKubeletCMFile"
    ssh root@$masterA "for node in \`kubectl get node -l node-role.kubernetes.io/master=\"\" --template='{{range .items}}{{.metadata.name}} {{end}}'\`; do \
                           kubectl patch node \$node -p '{\"spec\":{\"configSource\":{\"configMap\":{\"name\":\"$masterKubeletCM\",\"namespace\":\"kube-system\",\"kubeletConfigKey\":\"kubelet\"}}}}';
                       done"
    ssh root@$masterA "for node in \`kubectl get node -l node-role.kubernetes.io/node=\"\" --template='{{range .items}}{{.metadata.name}} {{end}}'\`; do \
                           kubectl patch node \$node -p '{\"spec\":{\"configSource\":{\"configMap\":{\"name\":\"$nodeKubeletCM\",\"namespace\":\"kube-system\",\"kubeletConfigKey\":\"kubelet\"}}}}';
                       done"
    ssh root@$masterA "for node in \`kubectl get node -l node-role.kubernetes.io/infra=\"\" --template='{{range .items}}{{.metadata.name}} {{end}}'\`; do \
                           kubectl patch node \$node -p '{\"spec\":{\"configSource\":{\"configMap\":{\"name\":\"$infraKubeletCM\",\"namespace\":\"kube-system\",\"kubeletConfigKey\":\"kubelet\"}}}}';
                       done"
fi

echo_task "install etcd-tool"
if [[ $skipped -ne 1 ]]; then
    if [[ "$enableEtcdTool" == "true" ]]; then
        # etcdIPs is a string, not an array, but it's ok for for-loop
        etcdIPs=`get_etcd_ips_string $clusterName`
        etcdEndpoints=""
        for ip in ${etcdIPs[@]}; do
            if [[ $etcdEndpoints == "" ]]; then
                etcdEndpoints="https://$ip:2379"
            else
                etcdEndpoints="https://$ip:2379,$etcdEndpoints"
            fi
        done
        tmpData="data.tmp.`date +%s`"
        cat $rootPath/infra.yml >> $tmpData
        echo "etcd_endpoints: \"$etcdEndpoints\"" >> $tmpData
        jinja2 $templatePath/etcd-tool-deploy.yml.j2 $tmpData --format=yaml >> etcd-tool-deploy.yml
        rm -f $tmpData

        scp etcd-tool-deploy.yml root@$masterA:.
        ssh root@$masterA "kubectl apply -f ~/etcd-tool-deploy.yml; \
                           rm -f ~/etcd-tool-deploy.yml"
        rm -f etcd-tool-deploy.yml
    else
        echo "Skipped, since etcd tool not enabled"
    fi
fi

echo_task "install kubectl completion"
if [[ $skipped -ne 1 ]]; then
    fName="install_kubectl_completion.sh"
    for ip in ${masterIPs[@]}; do
        ssh root@$ip "curl $pkgRepo/$fName -o $fName && bash $fName && rm -f $fName"
    done
fi

echo_task "dispatch cluster infra charts"
if [[ $skipped -ne 1 ]]; then
    bash $scriptPath/dispatch_charts.sh $clusterName
fi

echo_task "install helm client on cluster masters"
if [[ $skipped -ne 1 ]]; then
    for ip in ${masterIPs[@]}; do
        ssh root@$ip "curl $pkgRepo/helm/v2.14.3/linux/amd64/helm -o /usr/sbin/helm && chmod u+x /usr/sbin/helm && helm init"
    done
fi

echo_task "add cluster infra helm repo"
if [[ $skipped -ne 1 ]]; then
    for ip in ${masterIPs[@]}; do
        ssh root@$ip "helm repo add infra $chartRepo/$clusterName/infra"
    done
fi

echo_task "install ingress"
if [[ $skipped -ne 1 ]]; then
    userPrefer=`cat $clusterFile | awk '/^ingress_prefer:/{print $2}'`
    if [[ -z $userPrefer || $userPrefer == "" ]]; then
        userPrefer=$defaultIngress
    fi
    if [[ `grep supportedIngressControllers $versionPath/common | grep -c $userPrefer` -eq 0 ]]; then
        echo "cluster defined ingress_prefer not found in supportedIngressControllers, try to use default $defaultIngress"
        userPrefer=$defaultIngress
    fi
    if [[ $userPrefer == "traefik" ]]; then
        ssh root@$masterA "helm repo update; helm del --purge ingress-tfk; helm install infra/traefik --name ingress-tfk --namespace kube-system"
    elif [[ $userPrefer == "nginx" ]]; then
        ssh root@$masterA "helm repo update; helm del --purge nginx-ingress; helm install infra/nginx-ingress --set-string controller.nodeSelector.'node-role\.kubernetes\.io\/master=' --name nginx-ingress --namespace kube-system"
    fi
fi

echo_task "install kube-oidc"
if [[ $skipped -ne 1 ]]; then
    ssh root@$masterA "helm repo update; helm del --purge koidc; helm install infra/kube-oidc --name koidc --namespace kube-system --set-file loginapp.issuerCA=/etc/ssl/dex/ca.pem --set-file dex.secret.tls.crt=/etc/ssl/dex/cert.pem --set-file dex.secret.tls.key=/etc/ssl/dex/key.pem"
fi

echo_task "rolebinding for administrator"
if [[ $skipped -ne 1 ]]; then
    ssh root@$masterA "kubectl create clusterrolebinding cluster-administrator --clusterrole=cluster-admin --user=${oidcUsernamePrefix}administrator"
fi

echo_task "install prometheus-operator"
if [[ $skipped -ne 1 ]]; then
    if [[ $enablePrometheus == "true" ]]; then
        chartRepo="infra"
        if [[ $harborWithChartmusuem == "true" ]]; then
            chartRepo="stable"
        fi
        ssh root@$masterA "helm repo update; helm install $chartRepo/prometheus-operator --name prometheus-operator"
    else
        echo "Skipped, since prometheus not enabled"
    fi
fi

echo_task "install kube-prometheus"
if [[ $skipped -ne 1 ]]; then
    if [[ $enablePrometheus == "true" ]]; then
        iplist=`echo ${masterIPs[@]} | sed 's/ /,/g'`
        iplist="{"$iplist"}"
        ssh root@$masterA "kubectl -n monitoring create secret generic etcd-certs \
                               --from-file=/etc/ssl/etcd/ssl/ca.pem \
                               --from-file=/etc/ssl/etcd/ssl/node-\`hostname\`.pem \
                               --from-file=/etc/ssl/etcd/ssl/node-\`hostname\`-key.pem; \
                           helm repo update; helm install infra/kube-prometheus --name kube-prometheus \
                               --set clusterName=$clusterName,masters=\"$iplist\",masterAname=\`hostname\`"
    else
        echo "Skipped, since prometheus not enabled"
    fi
fi

echo_task "install prometheus-rules, grafana-dashboardDefinitions"
if [[ $skipped -ne 1 ]]; then
    if [[ $enablePrometheus == "true" ]]; then
        for fName in prometheus-rules.yaml grafana-dashboardDefinitions.yaml; do
            ssh root@$masterA "curl $pkgRepo/prometheus/manifests/$fName -o $fName && kubectl apply -f $fName && rm -f $fName"
        done
    else
        echo "Skipped, since prometheus not enabled"
    fi
fi

echo_task "install kube-prometheus-ldap"
if [[ $skipped -ne 1 ]]; then
    if [[ $enablePrometheus == "true" ]]; then
        chartRepo="infra"
        if [[ $harborWithChartmusuem == "true" ]]; then
            chartRepo="stable"
        fi
        ssh root@$masterA "helm repo update; helm install $chartRepo/kube-prometheus-ldap --name kube-prometheus-ldap --set clusterName=$clusterName"
    else
        echo "Skipped, since prometheus not enabled"
    fi
fi
