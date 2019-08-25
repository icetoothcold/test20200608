yum install -y nfs-utils
# or: cd nfsutils/ ; yum localinstall ./*
mkdir /nfsdata
mount -vt nfs -o vers=4.1 192.168.100.1:/ /nfsdata
