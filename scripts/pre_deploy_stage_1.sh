rootPath="$(cd `dirname $0`; cd .. ; pwd)"
source $rootPath/scripts/utils.sh

pre_deploy_check $1
if [[ $checkFailed -eq 1 ]]; then
    exit 1
fi

clusterName=$1
clusterFile=$clusterPath/$1.yml
parse_cluster_file
if [[ $parseFailed -eq 1 ]]; then
    exit 1
fi

echo "insert deployer key to host authorized_keys"
for ip in ${hostIPs[@]}; do
    rootPw=`grep $ip $clusterFile | awk '{print $2}'`
    ssh_authorize $ip $rootPw
done

echo "insert repos IP to /etc/hosts"
insert_infra_hosts

echo "backup host repo, and install private repo"
for ip in ${hostIPs[@]}; do
    ssh root@$ip "$CMD_BACKUP_YUM_REPOS ; curl $pkgRepo/private.repo -o /etc/yum.repos.d/private.repo"
done

echo "stop firewalld"
for ip in ${hostIPs[@]}; do
    ssh root@$ip "$CMD_DISABLE_FIREWALLD"
done

pushd $rootPath/kubespray
if [[ $force == "true" ]]; then
    rm -rf inventory/$clusterName
elif [[ -d inventory/$clusterName ]]; then
    echo "cluster $clusterName already exist, cannot redeploy it"
    echo "set 'force' to true in your cluster file $clusterFile to forcely redeploy"
    exit 1
fi

cp -r inventory/sample/ inventory/$clusterName
CONFIG_FILE=inventory/$clusterName/hosts.yml python3 contrib/inventory_builder/inventory.py ${hostIPs[@]}

ts=`date +%s`
cat $versionPath/common  $versionPath/$kubeVersion $rootPath/infra.yml $clusterFile | egrep -v "(^#|^$)" >> data.tmp$ts
echo "clusterName: $clusterName" >> data.tmp$ts
echo -e "\n\ntemplate render with data:"
cat data.tmp$ts
echo -e "\n"
jinja2 $templatePath/docker.yml data.tmp$ts --format=yaml >> docker.yml.tmp$ts
jinja2 $templatePath/k8s-cluster.yml data.tmp$ts --format=yaml >> k8s-cluster.yml.tmp$ts
cat docker.yml.tmp$ts >> inventory/$clusterName/group_vars/all/docker.yml
cat k8s-cluster.yml.tmp$ts >> inventory/$clusterName/group_vars/k8s-cluster/k8s-cluster.yml

sed -i '/^###- CUSTEMIZE FIELDS BEGIN -###$/,$d' roles/download/defaults/main.yml
cat roles/download/defaults/main.yml $templatePath/download_main.yml >> download_main.yml.tmp$ts
diff_and_cp download_main.yml.tmp$ts roles/download/defaults/main.yml

rm -f data.tmp$ts docker.yml.tmp$ts k8s-cluster.yml.tmp$ts download_main.yml.tmp$ts

# enable helm
diff_and_cp $templatePath/addons.yml inventory/$clusterName/group_vars/k8s-cluster/addons.yml
# yum repos
diff_and_cp $templatePath/container-engine_containerd_tasks_containerd_repo.yml roles/container-engine/containerd/tasks/containerd_repo.yml
diff_and_cp $templatePath/container-engine_containerd_templates_rh_containerd.repo.j2 roles/container-engine/containerd/templates/rh_containerd.repo.j2
diff_and_cp $templatePath/container-engine_docker_tasks_main.yml roles/container-engine/docker/tasks/main.yml
diff_and_cp $templatePath/container-engine_docker_templates_rh_docker.repo.j2 roles/container-engine/docker/templates/rh_docker.repo.j2
# kube-oidc
diff_and_cp $templatePath/kubeadm-config.v1beta1.yaml.j2 roles/kubernetes/master/templates/kubeadm-config.v1beta1.yaml.j2
diff_and_cp $templatePath/kubeadm-config.v1beta2.yaml.j2 roles/kubernetes/master/templates/kubeadm-config.v1beta2.yaml.j2
# coredns, nodelocaldns
diff_and_cp $templatePath/coredns-config.yml.j2 roles/kubernetes-apps/ansible/templates/coredns-config.yml.j2
diff_and_cp $templatePath/nodelocaldns-config.yml.j2 roles/kubernetes-apps/ansible/templates/nodelocaldns-config.yml.j2
diff_and_cp $templatePath/coredns-deployment.yml.j2 roles/kubernetes-apps/ansible/templates/coredns-deployment.yml.j2


popd

echo "Pre-deploy stage-1 jobs done, modify $inventoryPath/$clusterName/hosts.yml to fit you cluster plan"
echo "after that, run:"
echo -e "\t$scriptPath/pre_deploy_stage_2.sh $clusterName"
