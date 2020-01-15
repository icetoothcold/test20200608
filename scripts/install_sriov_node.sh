#!/bin/bash

# scripts/pre_deploy_stage_1.sh should run to config /etc/hosts, yum repo, etc...

# node should be deployed, and join k8s cluster already

# refer docs/sriov_cni.rst

repoUrl="http://local.repo.io:8080"

curl -o /opt/cni/bin/sriovMGR $repoUrl/srvioMGR && chmod +x /opt/cni/bin/sriovMGR

curl -o /opt/cni/bin/sriov-cni $repoUrl/srvioMGR && chmod +x /opt/cni/bin/sriov-cni

cat << EOF > "/etc/cni/net.d/10-default.conf"
{
    "cniVersion": "0.2.0",
    "name": "mynet",
    "type": "sriov-cni",
    "shellDir": "/opt/cni/bin",
    "noCheckVolumePath": false,
    "master": "https://localhost:6443",
    "kubeConfig": "/etc/kubernetes/kubelet.conf",
    "totoalvfs": 63
}
EOF

yum install -y jq

echo "systemctl stop kubelet" >> /etc/rc.d/rc.local
echo "rm -rf /var/run/sriov && mkdir /var/run/sriov && chown kube /var/run/sriov" >> /etc/rc.d/rc.local
echo "systemctl start kubelet" >> /etc/rc.d/rc.local
