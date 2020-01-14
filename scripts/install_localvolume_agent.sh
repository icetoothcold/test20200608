#!/bin/bash

function get_node_ips_strings
{
    python3 -c "import yaml; all=yaml.safe_load(open('$inventoryPath/$1/hosts.yml'))['all']; print(' '.join([all['hosts'][host]['ip'] for host in all['hosts'] if host in all['children']['kube-node']['hosts']]))"
}

rootPath="$(cd `dirname $0`; cd .. ; pwd)"
inventoryPath=$rootPath/kubespray/inventory
clusterName=$1
nodeIPs=`get_node_ips_strings $clusterName`

echo "install local volume provisioner on every node."
for node in ${nodeIPs[@]};do
  ssh root@$node '
pkgRepo="http://local.repo.io:8080"

# biniary file
curl -O ${pkgRepo}/agent-manager /usr/local/bin && chmod +x /usr/local/bin/agent-manager

# local volume scripts
curl -O ${pkgRepo}/csi-scripts.tar
tar xvf csi-scripts.tar -C /opt

cat << EOF > /usr/lib/systemd/system/local-volume-provisioner.service
[Unit]
Description=Local Volume Provisioner

[Service]
Type=simple
Environment=HOSTNAME=`hostname -s`
ExecStart=/usr/local/bin/agent-manager -kubeconfig=/etc/kubernetes/kubelet.conf -hostname=$HOSTNAME  -shelldir=/opt/csi-scripts
Restart=always
TimeoutSec=2
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl enable local-volume-provisioner.service
systemctl start local-volume-provisioner.service
'
  echo "Task is done on $node."
done
