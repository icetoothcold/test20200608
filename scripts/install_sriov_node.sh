#!/bin/bash

# scripts/pre_deploy_stage_1.sh should run to config /etc/hosts, yum repo, etc...

# node should be deployed, and join k8s cluster already

# refer docs/sriov_cni.rst

rootPath="$(cd `dirname $0`; cd .. ; pwd)"
source $rootPath/scripts/utils.sh

all_cni_bins="calico calico-ipam flannel host-local loopback portmap tuning sriovMGR sriov-cni"
all_cni_confs="sriov-cni.conf"
all_cnis="$all_cni_bins $all_cni_confs"
for cni in ${all_cnis[@]}; do
    if [[ ! -f $rpmsPath/all-cnis/$cni ]]; then
        echo "CNI bin file $cni is missing in $rpmsPath/all-cnis"
    fi
done

declare -a rc_local_contents
rc_local_contents+=("systemctl#stop#kubelet")
rc_local_contents+=("rm#-rf#/var/run/sriov#&&#mkdir#/var/run/sriov#&&#chown#kube#/var/run/sriov")
rc_local_contents+=("systemctl#start#kubelet")

for ip in ${hostIPs[@]}; do
    ssh root@$ip "mkdir -p /var/run/sriov && chown kube /var/run/sriov && yum install -y jq"

    for bin in ${all_cni_bins[@]}; do
        ssh root@$ip "mkdir -p /opt/cin/bin && chown kube /opt/cin && chown kube /opt/cin/bin && curl -o /opt/cni/bin/$bin $pkgRepo/$bin && chmod +x /opt/cni/bin/$bin"
    done

    for conf in ${all_cni_confs[@]}; do
        ssh root@$ip "mkdir -p /etc/cin/bin && chown kube /etc/cin && chown kube /etc/cin/net.d && curl -o /etc/cni/net.d/$conf $pkgRepo/$conf"
    done

    rclocal="/etc/rc.d/rc.local"
    for c in ${rc_local_contents[@]}; do
       cwrap=`echo $c | sed 's/#/ /g'`
       ssh root@$ip "grep -q $cwrap $rclocal || echo $cwrap >> $rclocal"
    done
done
