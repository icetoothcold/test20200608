rootPath="$(cd `dirname $0`; cd .. ; pwd)"
dexDNS=`cat $rootPath/infra.yml | awk -F'"' '/dexDNS/{print $2}'`
loginappDNS=`cat $rootPath/infra.yml | awk -F'"' '/loginappDNS/{print $2}'`

source $rootPath/scripts/utils.sh

if [[ -z $1 ]]; then
    echo "No cluster name assigned"
    exit 1
fi
if [[ ! -d $inventoryPath/$1 ]]; then
    echo "Your cluster not found in $inventoryPath, try to run $scriptPath/pre_deploy_stage_1.sh first!"
    exit 1
fi

clusterName=$1

echo "generate dex CA files"
bash $scriptPath/verify_and_gen_dex_CA.sh $clusterName $dexDNS

# masterIPs is a string, not an array, but it's ok for for-loop
masterIPs=`get_master_ips_string $clusterName`

echo "push dex CA files to masters /etc/ssl/dex"
for ip in ${masterIPs[@]}; do
    ssh root@$ip "mkdir -p /etc/ssl/dex"
    scp $clusterPath/${1}_dex_ca/* root@$ip:/etc/ssl/dex/
done

# etcdIPs is a string, not an array, but it's ok for for-loop
etcdIPs=`get_etcd_ips_string $clusterName`
corednsEtcdEndpoints=""
for ip in ${etcdIPs[@]}; do
    if [[ $corednsEtcdEndpoints == "" ]]; then
        corednsEtcdEndpoints="https://$ip:2379"
    else
        corednsEtcdEndpoints="https://$ip:2379 $corednsEtcdEndpoints"
    fi
done
echo "coredns_etcd_plugin_endpoints: \"$corednsEtcdEndpoints\"" >> $inventoryPath/$clusterName/group_vars/k8s-cluster/k8s-cluster.yml

echo "Pre-deploy stage-2 jobs done, next use the follow command to deploy:"
echo -e "    ansible-playbook -i $inventoryPath/$clusterName/hosts.yml $rootPath/kubespray/cluster.yml -b --private-key=~/.ssh/id_rsa"
echo -e "\twith --user=root if current user on this node is root"
echo -e "\nAfter cluster deployed, run:"
echo -e "\t$scriptPath/post_deploy.sh $clusterName"
