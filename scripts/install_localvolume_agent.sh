#!/bin/bash

function get_node_ips_strings
{
    python3 -c "import yaml; all=yaml.safe_load(open('$inventoryPath/$1/hosts.yml'))['all']; print(' '.join([all['hosts'][host]['ip'] for host in all['hosts'] if host in all['children']['kube-node']['hosts'] and host not in all['children']['kube-master']['hosts']]))"
}

function get_node_name_strings
{
    python3 -c "import yaml; all=yaml.safe_load(open('$inventoryPath/$1/hosts.yml'))['all'];print(' '.join(host for host in all['hosts'].keys() if host in all['children']['kube-node']['hosts'] and host not in all['children']['kube-master']['hosts'])) "
}

rootPath="$(cd `dirname $0`; cd .. ; pwd)"
inventoryPath=$rootPath/kubespray/inventory
clusterName=$1

source $rootPath/scripts/utils.sh

nodeIPs=`get_node_ips_strings $clusterName`
nodeNames=`get_node_name_strings $clusterName`

# masterIPs is a string, not an array, but it's ok for for-loop
masterIPs=`get_master_ips_string $clusterName`
masterA=`echo $masterIPs | cut -d ' ' -f 1`

echo "add annotation for node"
ssh root@$masterA "
for node in $nodeNames;do
  echo \"add annotation on node \$node\"
  kubectl annotate node \$node alcor.host.vgs='{\"vgdata1\": \"high\"}'
done
"
exit

echo ""
echo ""

echo "install local volume provisioner on every node."
for node in ${nodeIPs[@]};do
  echo "install local volume provisioner on node $node."
  ssh root@$node '
pkgRepo="http://local.repo.io:8080"

# biniary file
curl -o /usr/local/bin/agent-manager ${pkgRepo}/agent-manager && chmod +x /usr/local/bin/agent-manager

# local volume scripts
curl -o /opt/csi-scripts.tar ${pkgRepo}/csi-scripts.tar
tar xvf /opt/csi-scripts.tar -C /opt

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

sleep 2
echo ""
echo ""
echo "Status of local-volume-provisioner"
echo "##################################"
systemctl status local-volume-provisioner.service
echo "##################################"
echo ""
echo ""
'
  if [ $? -ne 0 ]; then
    echo "Task is failed on $node." 
  fi 
  echo "Task is done on $node."
done

