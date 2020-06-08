pvcreate /dev/vdb
vgcreate vgdata /dev/vdb
lvcreate -L 50G -n etcd vgdata
lvcreate -L 50G -n docker vgdata
lvcreate -L 50G -n kubelet vgdata
lvcreate -L 100G -n prometheus vgdata
lvcreate -L 100G -n elasticsearch vgdata

mkfs.xfs /dev/mapper/vgdata-etcd
mkfs.xfs /dev/mapper/vgdata-docker
mkfs.xfs /dev/mapper/vgdata-kubelet
mkfs.xfs /dev/mapper/vgdata-prometheus
mkfs.xfs /dev/mapper/vgdata-elasticsearch

etcduuid=`blkid|grep etcd|awk -F"\"" '{print $2}'`
dockeruuid=`blkid|grep docker|awk -F"\"" '{print $2}'`
kubeletuuid=`blkid|grep kubelet|awk -F"\"" '{print $2}'`
prometheusuuid=`blkid|grep prometheus|awk -F"\"" '{print $2}'`
elasticsearchuuid=`blkid|grep elasticsearch|awk -F"\"" '{print $2}'`

echo "UUID=$etcduuid /var/lib/etcd xfs defaults 0 0" >> /etc/fstab
echo "UUID=$dockeruuid /var/lib/docker xfs defaults 0 0" >> /etc/fstab
echo "UUID=$kubeletuuid /var/lib/kubelet xfs defaults 0 0" >> /etc/fstab
echo "UUID=$prometheusuuid /monitoring/prometheus xfs defaults 0 0" >> /etc/fstab
echo "UUID=$elasticsearchuuid /logging/elasticsearch xfs defaults 0 0" >> /etc/fstab

mkdir /var/lib/etcd
mkdir /var/lib/docker
mkdir /var/lib/kubelet
mkdir -p /monitoring/prometheus
mkdir -p /logging/elasticsearch
mkdir -p /opt/alertmanager/data
mkdir -p /opt/grafana/data

mount -a

chmod 777 /monitoring/prometheus
chmod 777 /logging/elasticsearch
chmod 777 /opt/alertmanager/data
chmod 777 /opt/grafana/data