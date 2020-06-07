#!/bin/bash
skipFirstN=0
skipLastFrom=0
notSkip=()

function get_node_ips_strings
{
    python3 -c "import yaml; all=yaml.safe_load(open('$inventoryPath/$1/hosts.yml'))['all']; print(' '.join([all['hosts'][host]['ip'] for host in all['hosts'] if host in all['children']['kube-node']['hosts'] and host not in all['children']['kube-master']['hosts']]))"
}


rootPath="$(cd `dirname $0`; cd .. ; pwd)"
inventoryPath=$rootPath/kubespray/inventory
clusterName=$1

source $rootPath/scripts/utils.sh

nodeIPs=`get_node_ips_strings $clusterName`
masterIPs=`get_master_ips_string $clusterName`

echo_task "init master lvm"
if [[ $skipped -ne 1 ]];then
	for master in ${masterIPs[@]};do
	  echo "init lvm on master $master."
	  scp $rootPath/scripts/master-lvm.sh $master:/tmp/master-lvm.sh
	  ssh root@$master 'sh /tmp/master-lvm.sh'
	  if [ $? -ne 0 ]; then
		echo "Task is failed on $master." 
	  fi 
	  echo "Task is done on $master."
	done
fi

echo_task "init node lvm"
if [[ $skipped -ne 1 ]];then
	for node in ${nodeIPs[@]};do
	  echo "init lvm on node $node."
	  scp $rootPath/scripts/part-vdb.sh $node:/tmp/part-vdb.sh
	  ssh root@$node 'fdisk /dev/vdb < /tmp/part-vdb.sh'
	  scp $rootPath/scripts/node-lvm.sh $node:/tmp/node-lvm.sh
	  ssh root@$node 'sh /tmp/node-lvm.sh'
	  if [ $? -ne 0 ]; then
		echo "Task is failed on $node." 
	  fi 
	  echo "Task is done on $node."
	done
fi
