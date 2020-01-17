#!/bin/bash

# scripts/pre_deploy_stage_1.sh should run to config /etc/hosts, yum repo, etc...

# node should be deployed, and join k8s cluster already

# refer docs/sriov_cni.rst

repoUrl="http://local.repo.io:8080"

curl -o /opt/cni/bin/sriovMGR $repoUrl/sriovMGR && chmod +x /opt/cni/bin/sriovMGR

curl -o /opt/cni/bin/sriov-cni $repoUrl/sriov-cni && chmod +x /opt/cni/bin/sriov-cni

# FIXME:
# master1 上的/opt/cni/bin/下的二进制文件要先拷到infra的rpms_and_files/all-cnis（目录需要创建) 目录下
# calico  calico-ipam  flannel  host-local  loopback  portmap  tuning
curl -o /opt/cni/bin/calico $repoUrl/all-cnis/calico && chmod +x /opt/cni/bin/calico
curl -o /opt/cni/bin/calico-ipam $repoUrl/all-cnis/calico-ipam && chmod +x /opt/cni/bin/calico-ipam
curl -o /opt/cni/bin/flannel $repoUrl/all-cnis/flannel && chmod +x /opt/cni/bin/flannel
curl -o /opt/cni/bin/host-local $repoUrl/all-cnis/host-local && chmod +x /opt/cni/bin/host-local
curl -o /opt/cni/bin/loopback $repoUrl/all-cnis/loopback && chmod +x /opt/cni/bin/loopback
curl -o /opt/cni/bin/portmap $repoUrl/all-cnis/portmap && chmod +x /opt/cni/bin/portmap
curl -o /opt/cni/bin/tuning $repoUrl/all-cnis/tuning && chmod +x /opt/cni/bin/tuning

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

mkdir /var/run/sriov && chown kube /var/run/sriov

yum install -y jq

echo "systemctl stop kubelet" >> /etc/rc.d/rc.local
echo "rm -rf /var/run/sriov && mkdir /var/run/sriov && chown kube /var/run/sriov" >> /etc/rc.d/rc.local
echo "systemctl start kubelet" >> /etc/rc.d/rc.local
