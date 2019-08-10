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

echo_task "install kubectl completion"
if [[ $skipped -ne 1 ]]; then
    ctlcmpl="install_kubectl_completion.sh"
    for ip in ${masterIPs[@]}; do
        ssh root@$ip "curl $pkgRepo/$ctlcmpl -o $ctlcmpl && bash $ctlcmpl && rm -f $ctlcmpl"
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

echo_task "install ingress/traefik"
if [[ $skipped -ne 1 ]]; then
    ssh root@$masterA "helm repo update; helm del --purge ingress-tfk; helm install infra/traefik --name ingress-tfk --namespace kube-system"
fi

echo_task "install keepalived-vip"
if [[ $skipped -ne 1 ]]; then
    ssh root@$masterA "helm repo update; helm del --purge kpvip; helm install infra/keepalived-vip --name kpvip --namespace kube-system"
fi

echo_task "install kube-oidc"
if [[ $skipped -ne 1 ]]; then
    ssh root@$masterA "helm repo update; helm del --purge koidc; helm install infra/kube-oidc --name koidc --namespace kube-system --set-file loginapp.issuerCA=/etc/ssl/dex/ca.pem --set-file dex.secret.tls.crt=/etc/ssl/dex/cert.pem --set-file dex.secret.tls.key=/etc/ssl/dex/key.pem"
fi
