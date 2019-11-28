ts=`date "+%Y%m%d.%H%M%S"`
mkdir /etc/ssl/etcd/ssl/bak.$ts
mv /etc/ssl/etcd/ssl/*.pem /etc/ssl/etcd/ssl/bak.$ts

dnsIdx=`grep 'DNS' openssl.conf | tail -n 1 | awk '{print $1}' | awk -F'.' '{print $2}'`
dnsIdx=$((dnsIdx+1))
echo "DNS.$dnsIdx = node2" >> openssl.conf 
dnsIdx=$((dnsIdx+1))
echo "DNS.$dnsIdx = node3" >> openssl.conf 

ipIdx=`grep 'IP' openssl.conf | tail -n 1 | awk '{print $1}' | awk -F'.' '{print $2}'`
ipIdx=$((ipIdx+1))
echo "IP.$ipIdx = 192.168.122.62" >> openssl.conf 
ipIdx=$((ipIdx+1))
echo "IP.$ipIdx = 192.168.122.66" >> openssl.conf 

MASTERS="node1 node2 node3" HOSTS="node1 node2 node3" /usr/local/bin/etcd-scripts/make-ssl-etcd.sh -f /etc/ssl/etcd/openssl.conf -d /etc/ssl/etcd/ssl/
scp -r *.pem root@node2:/etc/ssl/etcd/ssl/
scp -r *.pem root@node3:/etc/ssl/etcd/ssl/

docker rm -f etcd1
