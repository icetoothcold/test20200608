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

myKubeletCM="my-kubelet-cm"
myKubeletCMFile="/etc/kubernetes/my-kubelet-config.yaml"
echo_task "config kubelet dynamic configuration"
if [[ $skipped -ne 1 ]]; then
    ssh root@$masterA "kubectl -n kube-system delete cm $myKubeletCM; \
                       cp -f /etc/kubernetes/kubelet-config.yaml $myKubeletCMFile; \
                       sed -i 's/^address:.*/address: 0.0.0.0/g' $myKubeletCMFile; \
                       kubectl -n kube-system create cm $myKubeletCM --from-file=kubelet=$myKubeletCMFile"
    ssh root@$masterA "for node in \`kubectl get node --template='{{range .items}}{{.metadata.name}} {{end}}'\`; do \
                           kubectl patch node \$node -p '{\"spec\":{\"configSource\":{\"configMap\":{\"name\":\"$myKubeletCM\",\"namespace\":\"kube-system\",\"kubeletConfigKey\":\"kubelet\"}}}}';
                       done"
fi

echo_task "install etcd-tool"
if [[ $skipped -ne 1 ]]; then
    if [[ "$enableEtcdTool" == "true" ]]; then
        scp $templatePath/etcd-tool-deploy.yaml root@$masterA:.
        ssh root@$masterA "kubelet apply -f ~/etcd-tool-deploy.yml; \
                           rm -f ~/etcd-tool-deploy.yml"
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
        ssh root@$masterA "helm repo update; helm install infra/prometheus-operator --name prometheus-operator"
    else
        echo "Skipped, since prometheus not enabled"
    fi
fi

echo_task "install kube-prometheus"
if [[ $skipped -ne 1 ]]; then
    if [[ $enablePrometheus == "true" ]]; then
        iplist=`echo ${masterIPs[@]} | sed 's/ /,/g'`
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

echo_task "install prometheus-rules, grafana-dashboardDefinations"
if [[ $skipped -ne 1 ]]; then
    if [[ $enablePrometheus == "true" ]]; then
        for fName in "prometheus-rules.yaml grafana-dashboardDefinations.yaml"; do
            ssh root@$masterA "curl $pkgRepo/prometheus/manifests/$fName -o $fName && kubectl apply -f $fName && rm -f $fName"
        done
    else
        echo "Skipped, since prometheus not enabled"
    fi
fi

echo_task "install kube-prometheus-ldap"
if [[ $skipped -ne 1 ]]; then
    if [[ $enablePrometheus == "true" ]]; then
        ssh root@$masterA "helm repo update; helm install infra/kube-prometheus-ldap --name kube-prometheus \
                               --set clusterName=$clusterName"
    else
        echo "Skipped, since prometheus not enabled"
    fi
fi
