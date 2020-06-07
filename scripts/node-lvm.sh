pvcreate /dev/vdb1
pvcreate /dev/vdb2
vgcreate vgdata /dev/vdb1
vgcreate vgdata1 /dev/vdb2
lvcreate -L 100G -n docker vgdata
lvcreate -l +100%FREE -n kubelet vgdata

mkfs.xfs /dev/mapper/vgdata-docker
mkfs.xfs /dev/mapper/vgdata-kubelet

dockeruuid=`blkid|grep docker|awk -F"\"" '{print $2}'`
kubeletuuid=`blkid|grep kubelet|awk -F"\"" '{print $2}'`

echo "UUID=$dockeruuid /var/lib/docker xfs defaults 0 0" >> /etc/fstab
echo "UUID=$kubeletuuid /var/lib/kubelet xfs defaults 0 0" >> /etc/fstab

mkdir /var/lib/docker
mkdir /var/lib/kubelet

mount -a