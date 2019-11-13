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
repoMd5=`curl -s $pkgRepo/private.repo | md5sum | awk '{print $1}'`
for ip in ${hostIPs[@]}; do
    ssh root@$ip "if [[ ! -d /etc/yum.repos.d/bak ]]; then \
                      mkdir /etc/yum.repos.d/bak; \
                  fi ; \
                  if [[ ! -f /etc/yum.repos.d/private.repo || `md5sum /etc/yum.repos.d/private.repo | awk '{print $1}'` != "$repoMd5" ]]; then \
                      mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak; \
                      curl $pkgRepo/private.repo -o /etc/yum.repos.d/private.repo ; \
                  fi"
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

tmp="tmp.`date +%s`"
# prepare render source data
cat $versionPath/common  $versionPath/$kubeVersion $rootPath/infra.yml $clusterFile | egrep -v "(^#|^$)" >> data.$tmp
echo "clusterName: $clusterName" >> data.$tmp
echo -e "\n\ntemplate render with data:"
cat data.$tmp
echo -e "\n"

# render our docker.yml, and append to custom cluster docker.yml
jinja2 $templatePath/docker.yml data.$tmp --format=yaml >> docker.yml.$tmp
cat docker.yml.$tmp >> inventory/$clusterName/group_vars/all/docker.yml
rm -f docker.yml.$tmp

# render our k8s-cluster.yml, and append to custom cluster k8s-cluster.yml
jinja2 $templatePath/k8s-cluster.yml data.$tmp --format=yaml >> k8s-cluster.yml.$tmp
cat k8s-cluster.yml.$tmp >> inventory/$clusterName/group_vars/k8s-cluster/k8s-cluster.yml
rm -f k8s-cluster.yml.$tmp

# render our download/main.yml, and append to inventory download/main.yml
#
# the line ###- CUSTEMIZE FIELDS BEGIN -### is head line in our template download_main.yml
sed -i '/^###- CUSTEMIZE FIELDS BEGIN -###$/,$d' roles/download/defaults/main.yml
cat roles/download/defaults/main.yml $templatePath/download_main.yml >> download_main.yml.$tmp
diff_and_cp download_main.yml.$tmp roles/download/defaults/main.yml
rm -f download_main.yml.$tmp

# enable addons: helm, dashboard
diff_and_cp $templatePath/addons.yml inventory/$clusterName/group_vars/k8s-cluster/addons.yml

# replace yum repos
diff_and_cp $templatePath/container-engine_containerd_tasks_containerd_repo.yml roles/container-engine/containerd/tasks/containerd_repo.yml
diff_and_cp $templatePath/container-engine_containerd_templates_rh_containerd.repo.j2 roles/container-engine/containerd/templates/rh_containerd.repo.j2
diff_and_cp $templatePath/container-engine_docker_tasks_main.yml roles/container-engine/docker/tasks/main.yml
diff_and_cp $templatePath/container-engine_docker_templates_rh_docker.repo.j2 roles/container-engine/docker/templates/rh_docker.repo.j2

# for oracle, replace bootstrap-os main.yml
diff_and_cp $templatePath/bootstrap-os_main.yml roles/bootstrap-os/tasks/main.yml

# config kube-oidc
diff_and_cp $templatePath/kubeadm-config.v1beta1.yaml.j2 roles/kubernetes/master/templates/kubeadm-config.v1beta1.yaml.j2
diff_and_cp $templatePath/kubeadm-config.v1beta2.yaml.j2 roles/kubernetes/master/templates/kubeadm-config.v1beta2.yaml.j2

# config coredns, nodelocaldns
diff_and_cp $templatePath/coredns-config.yml.j2 roles/kubernetes-apps/ansible/templates/coredns-config.yml.j2
diff_and_cp $templatePath/nodelocaldns-config.yml.j2 roles/kubernetes-apps/ansible/templates/nodelocaldns-config.yml.j2
diff_and_cp $templatePath/coredns-deployment.yml.j2 roles/kubernetes-apps/ansible/templates/coredns-deployment.yml.j2
diff_and_cp $templatePath/coredns-ansible-tasks.yml roles/kubernetes-apps/ansible/tasks/coredns.yml
if [[ -f roles/kubernetes-apps/ansible/templates/coredns-secrets.yml.j2 ]]; then
    diff_and_cp $templatePath/coredns-secrets.yml.j2 roles/kubernetes-apps/ansible/templates/coredns-secrets.yml.j2
else
    cp $templatePath/coredns-secrets.yml.j2 roles/kubernetes-apps/ansible/templates/coredns-secrets.yml.j2
fi

rm -f data.$tmp

popd

echo "Pre-deploy stage-1 jobs done, modify $inventoryPath/$clusterName/hosts.yml to fit you cluster plan"
echo "after that, run:"
echo -e "\t$scriptPath/pre_deploy_stage_2.sh $clusterName"
